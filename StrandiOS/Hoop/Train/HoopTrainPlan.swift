#if os(iOS)
import Foundation
import WhoopStore

/// A gym session to run, before it becomes NOOP's `[LiftPlanItem]`. Built from what the person typed:
/// explicit lines ("Bench press 4x8 60kg") parse on the device; a description ("push day, 45 min,
/// dumbbells only") is planned by Hoop AI.
struct HoopTrainPlan: Equatable, Codable {
    struct Exercise: Equatable, Codable, Identifiable {
        var id = UUID()
        var name: String
        var sets: Int
        var repsLow: Int?
        var repsHigh: Int?
        var weightKg: Double?
        var restSec: Int?
        var rpe: Double?
        var primaryMuscle: String?
        var secondaryMuscles: [String] = []
        var note: String?

        /// "4 × 8–10 · 60 kg · rest 2:00"
        func summary(system: UnitSystem) -> String {
            var parts: [String] = []
            var reps = "\(sets) ×"
            if let lo = repsLow {
                reps += " \(lo)"
                if let hi = repsHigh, hi != lo { reps += "–\(hi)" }
            } else {
                reps = "\(sets) sets"
            }
            parts.append(reps)
            if let w = weightKg, w > 0 { parts.append(HoopTrainPlan.weightText(w, system: system)) }
            if let r = rpe { parts.append("RPE \(r.formatted(.number.precision(.fractionLength(0...1))))") }
            if let rest = restSec, rest > 0 {
                parts.append(String(localized: "rest \(rest / 60):\(String(format: "%02d", rest % 60))"))
            }
            return parts.joined(separator: " · ")
        }
    }

    var name: String
    var minutes: Int?
    var summary: String?
    var exercises: [Exercise]
    /// True when Hoop AI wrote it (shown as such); false when parsed from the person's own lines.
    var fromAI = false

    /// The session NOOP's gym engine runs.
    var liftPlan: [LiftPlanItem] {
        exercises.map { e in
            let primary = e.primaryMuscle.flatMap(LiftMuscle.init(rawValue:)) ?? HoopMuscleGuess.primary(for: e.name)
            var secondary = e.secondaryMuscles.compactMap(LiftMuscle.init(rawValue:))
            if secondary.isEmpty { secondary = HoopMuscleGuess.secondary(for: e.name) }
            return LiftPlanItem(exercise: e.name,
                                primaryMuscle: primary,
                                secondaryMuscles: secondary.filter { $0 != primary },
                                targetSets: e.sets,
                                restSec: e.restSec,
                                targetRepsLow: e.repsLow,
                                targetRepsHigh: e.repsHigh,
                                targetRpe: e.rpe,
                                targetWeightKg: e.weightKg,
                                note: e.note)
        }
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    /// "60 kg", "62.5 kg", "135 lb": no trailing ".0".
    static func weightText(_ kg: Double, system: UnitSystem) -> String {
        let value = system == .imperial ? kg / 0.45359237 : kg
        let rounded = (value * 2).rounded() / 2
        let number = rounded.formatted(.number.precision(.fractionLength(0...1)))
        return system == .imperial ? "\(number) lb" : "\(number) kg"
    }
}

// MARK: - Parsing typed lines

/// Reads workouts written the way people write them: "Bench press 4x8 60kg", "Squat 5 x 5 @ 100",
/// "Pull-ups 3 sets of 8-10", "RDL 3x10 80kg rest 90s", one per line (or separated by ";" or ",").
enum HoopTrainParser {
    static func parse(_ text: String, system: UnitSystem) -> HoopTrainPlan? {
        var chunks: [String] = []
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\n;")) {
            let parts = line.components(separatedBy: ",")
            // Commas separate exercises only when more than one piece carries a sets x reps pattern.
            if parts.filter({ setsReps(in: $0) != nil }).count > 1 {
                chunks.append(contentsOf: parts)
            } else {
                chunks.append(line)
            }
        }
        let exercises = chunks.compactMap { parseLine($0, system: system) }.map { e -> HoopTrainPlan.Exercise in
            var e = e
            if let hi = e.repsHigh, let lo = e.repsLow, hi <= lo || hi > 100 { e.repsHigh = nil }
            return e
        }
        guard !exercises.isEmpty else { return nil }
        let name = exercises.count == 1 ? exercises[0].name : String(localized: "Your session")
        return HoopTrainPlan(name: name, minutes: nil, summary: nil, exercises: exercises, fromAI: false)
    }

    private static func parseLine(_ raw: String, system: UnitSystem) -> HoopTrainPlan.Exercise? {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard let sr = setsReps(in: line) else { return nil }
        line.removeSubrange(sr.range)

        var weightKg: Double?
        if let m = firstMatch(#"(?i)@?\s*(\d+(?:[.,]\d+)?)\s*(kg|kgs|kilos?|lb|lbs|pounds?)\b"#, in: line) {
            let value = Double(m.groups[0].replacingOccurrences(of: ",", with: ".")) ?? 0
            let unit = m.groups[1].lowercased()
            weightKg = unit.hasPrefix("l") || unit.hasPrefix("p") ? value * 0.45359237 : value
            line.removeSubrange(m.range)
        } else if let m = firstMatch(#"@\s*(\d+(?:[.,]\d+)?)"#, in: line) {
            let value = Double(m.groups[0].replacingOccurrences(of: ",", with: ".")) ?? 0
            weightKg = system == .imperial ? value * 0.45359237 : value
            line.removeSubrange(m.range)
        }

        var restSec: Int?
        if let m = firstMatch(#"(?i)rest\s*(\d+)\s*:\s*(\d{2})"#, in: line) {
            restSec = (Int(m.groups[0]) ?? 0) * 60 + (Int(m.groups[1]) ?? 0)
            line.removeSubrange(m.range)
        } else if let m = firstMatch(#"(?i)rest\s*(\d+)\s*(s|sec|secs|seconds|m|min|mins|minutes)?\b"#, in: line) {
            let n = Int(m.groups[0]) ?? 0
            let unit = m.groups[1].lowercased()
            restSec = unit.hasPrefix("m") ? n * 60 : (unit.isEmpty && n <= 5 ? n * 60 : n)
            line.removeSubrange(m.range)
        }

        var rpe: Double?
        if let m = firstMatch(#"(?i)rpe\s*(\d+(?:[.,]\d)?)"#, in: line) {
            rpe = Double(m.groups[0].replacingOccurrences(of: ",", with: "."))
            line.removeSubrange(m.range)
        }

        var name = line
            .replacingOccurrences(of: #"\s[-–—]+\s"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[:@|•*]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s\-–—.,]+|[\s\-–—.,]+$"#, with: "", options: .regularExpression)
            // Words left behind once the numbers are taken out ("rest", "at", "x", "of").
            .replacingOccurrences(of: #"(?i)\b(rest|at|of|x|with|sets?|reps?)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s\-–—.,]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = expandAbbreviations(name)
        guard !name.isEmpty else { return nil }
        return HoopTrainPlan.Exercise(name: name.prefix(1).uppercased() + name.dropFirst(),
                                      sets: max(1, min(sr.sets, 20)), repsLow: sr.low, repsHigh: sr.high,
                                      weightKg: weightKg, restSec: restSec, rpe: rpe)
    }

    /// Gym shorthand spelled out, so the session and its history read clearly.
    private static let abbreviations: [String: String] = [
        "ohp": "Overhead press", "rdl": "Romanian deadlift", "sldl": "Stiff-leg deadlift",
        "db": "Dumbbell", "bb": "Barbell", "kb": "Kettlebell", "bw": "Bodyweight",
        "bss": "Bulgarian split squat", "cgbp": "Close-grip bench press",
    ]

    private static func expandAbbreviations(_ name: String) -> String {
        name.split(separator: " ").map { word -> String in
            abbreviations[word.lowercased()] ?? String(word)
        }
        .joined(separator: " ")
    }

    /// "4x8", "4 × 8-10", "3 sets of 10", "3 sets x 12".
    private static func setsReps(in s: String) -> (sets: Int, low: Int?, high: Int?, range: Range<String.Index>)? {
        // The upper end of a rep range must not be a weight ("3x5 - 140kg" is 5 reps at 140 kg).
        let high = #"(?:\s*[-–]\s*(\d+)(?!\s*(?:kg|kgs|kilos?|lb|lbs|pounds?)\b)(?![\d.,]))?"#
        if let m = firstMatch(#"(?i)(\d+)\s*(?:sets?)?\s*[x×]\s*(\d+)"# + high + #"\s*(?:reps?)?"#, in: s) {
            return (Int(m.groups[0]) ?? 1, Int(m.groups[1]), m.groups[2].isEmpty ? nil : Int(m.groups[2]), m.range)
        }
        if let m = firstMatch(#"(?i)(\d+)\s*sets?\s*(?:of\s*)?(\d+)"# + high + #"\s*(?:reps?)?"#, in: s) {
            return (Int(m.groups[0]) ?? 1, Int(m.groups[1]), m.groups[2].isEmpty ? nil : Int(m.groups[2]), m.range)
        }
        return nil
    }

    private struct Match {
        let range: Range<String.Index>
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in s: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(m.range, in: s) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i -> String in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
        return Match(range: range, groups: groups)
    }
}

// MARK: - Muscle guesses

/// A best guess at which muscles an exercise trains, from its name, for lines typed without one. The
/// gym engine counts sets per muscle from this, so specific phrases are checked before generic ones.
enum HoopMuscleGuess {
    private static let table: [(keys: [String], primary: LiftMuscle, secondary: [LiftMuscle])] = [
        (["romanian", "rdl", "stiff leg", "good morning", "leg curl", "hamstring curl", "nordic"], .hamstrings, [.glutes, .lowerBack]),
        (["deadlift"], .hamstrings, [.glutes, .lowerBack, .upperBack]),
        (["hip thrust", "glute bridge", "glute", "kickback"], .glutes, [.hamstrings]),
        (["leg extension"], .quads, []),
        (["leg press", "squat", "lunge", "split squat", "step-up", "step up", "hack"], .quads, [.glutes, .adductors]),
        (["calf"], .calves, []),
        (["lateral raise", "side raise", "upright row"], .sideDelts, [.traps]),
        (["rear delt", "face pull", "reverse fly", "reverse flye"], .rearDelts, [.upperBack]),
        (["overhead press", "ohp", "shoulder press", "military", "arnold", "front raise"], .frontDelts, [.triceps, .sideDelts]),
        (["pushdown", "skull", "tricep", "triceps", "close grip", "close-grip"], .triceps, []),
        (["dip"], .triceps, [.chest, .frontDelts]),
        (["bench", "chest press", "push-up", "pushup", "push up", "fly", "flye", "pec deck", "crossover"], .chest, [.frontDelts, .triceps]),
        (["pull-up", "pullup", "pull up", "chin-up", "chinup", "chin up", "pulldown", "pull-down", "lat "], .lats, [.biceps, .upperBack]),
        (["shrug"], .traps, []),
        (["row"], .upperBack, [.lats, .biceps, .rearDelts]),
        (["hammer curl"], .biceps, [.forearms]),
        (["curl", "bicep", "biceps"], .biceps, [.forearms]),
        (["wrist", "forearm", "farmer"], .forearms, [.traps]),
        (["back extension", "hyperextension", "superman"], .lowerBack, [.glutes, .hamstrings]),
        (["russian twist", "side plank", "oblique", "woodchop"], .obliques, [.abs]),
        (["crunch", "plank", "sit-up", "situp", "leg raise", "hollow", "ab wheel", "abs"], .abs, [.obliques]),
    ]

    static func primary(for name: String) -> LiftMuscle? { match(name)?.primary }
    static func secondary(for name: String) -> [LiftMuscle] { match(name)?.secondary ?? [] }

    private static func match(_ name: String) -> (primary: LiftMuscle, secondary: [LiftMuscle])? {
        let n = " " + name.lowercased() + " "
        for row in table where row.keys.contains(where: { n.contains($0) }) {
            return (row.primary, row.secondary)
        }
        return nil
    }
}

// MARK: - Hoop AI planning

extension HoopAI {
    /// Plans a gym session from a description, adapting to today's recovery and recent training.
    func planWorkout(_ request: String, context: String, system: UnitSystem) async throws -> HoopTrainPlan {
        guard isConnected else { throw HoopAIClient.AIError.signedOut }
        let muscles = LiftMuscle.allCases.map(\.rawValue).joined(separator: ", ")
        let units = system == .imperial ? "pounds (convert to kg in the JSON)" : "kilograms"
        let prompt = """
        \(context)

        Plan my gym session for: "\(request)"

        If I listed exercises, keep them (fix obvious typos) and fill in anything missing. Otherwise design a \
        session that fits the request and my recovery today: lighter volume when recovery is low, harder \
        when it's high. Suggest starting weights only if my history makes them sensible; otherwise leave \
        weight null. I think in \(units).

        Reply with only a JSON object, no code fences:
        {"name": short session name, "minutes": estimated whole minutes, "summary": one sentence on the focus \
        and why it suits today, "exercises": [{"name": exercise name, "sets": integer, "reps_low": integer, \
        "reps_high": integer or null, "weight_kg": number or null, "rest_sec": integer, "rpe": number or null, \
        "primary_muscle": one of [\(muscles)], "secondary_muscles": [zero or more of the same list], \
        "note": one short technique or pacing cue}]}
        Use 3 to 8 exercises unless I asked otherwise.
        """
        let turns: [HoopAIClient.Turn] = [
            .init(role: .developer, text: HoopAI.systemPrompt + "\nFor workout plans, answer with JSON only."),
            .init(role: .user, text: prompt),
        ]
        let reply = try await HoopAIClient.complete(model: await readyModelForPlanning(), turns: turns)
        guard let plan = Self.parsePlan(reply) else {
            throw HoopAIClient.AIError.unsupported(String(localized: "Hoop AI couldn't turn that into a session. Try naming a few exercises."))
        }
        return plan
    }

    /// Exposed for planning, which lives outside the main HoopAI file.
    func readyModelForPlanning() async -> String {
        if models.isEmpty { await loadModels() }
        return model
    }

    static func parsePlan(_ reply: String) -> HoopTrainPlan? {
        var s = reply
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") { s = String(s[start...end]) }
        guard let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["exercises"] as? [[String: Any]] else { return nil }
        func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? Double).map { Int($0.rounded()) } ?? (v as? String).flatMap(Int.init) }
        func dbl(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? String).flatMap(Double.init) }
        let exercises: [HoopTrainPlan.Exercise] = rows.compactMap { r in
            guard let name = (r["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let sets = max(1, min(int(r["sets"]) ?? 3, 20))
            let low = int(r["reps_low"])
            var high = int(r["reps_high"])
            if let h = high, let l = low, h < l { high = nil }
            return HoopTrainPlan.Exercise(name: name, sets: sets, repsLow: low, repsHigh: high,
                                          weightKg: dbl(r["weight_kg"]).flatMap { $0 > 0 ? $0 : nil },
                                          restSec: int(r["rest_sec"]).map { max(0, min($0, 600)) },
                                          rpe: dbl(r["rpe"]),
                                          primaryMuscle: r["primary_muscle"] as? String,
                                          secondaryMuscles: r["secondary_muscles"] as? [String] ?? [],
                                          note: (r["note"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        guard !exercises.isEmpty else { return nil }
        return HoopTrainPlan(name: (json["name"] as? String) ?? String(localized: "Your session"),
                             minutes: int(json["minutes"]), summary: json["summary"] as? String,
                             exercises: exercises, fromAI: true)
    }
}
#endif
