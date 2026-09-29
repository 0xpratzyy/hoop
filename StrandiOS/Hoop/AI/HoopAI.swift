#if os(iOS)
import Combine
import Foundation
import SwiftUI
import UIKit
import WhoopStore
import StrandAnalytics

/// Hoop AI: the briefing on Today, Ask Hoop, the sleep insight and food estimates in Fuel, all answered by
/// the person's own ChatGPT plan. Off until they connect ChatGPT. Nothing is sent in the background: each
/// request is a direct result of something they tapped, and carries only a compact summary of their data.
@MainActor
final class HoopAI: ObservableObject {
    static let shared = HoopAI()

    let auth = HoopChatGPTAuth.shared

    @Published private(set) var models: [HoopAIClient.Model] = []
    /// The chosen model's slug; empty means the first model ChatGPT lists.
    @Published var modelSlug: String { didSet { UserDefaults.standard.set(modelSlug, forKey: "hoop.ai.model") } }
    /// Set once the plan-usage explainer has been seen after the first sign-in.
    @Published var welcomed: Bool { didSet { UserDefaults.standard.set(welcomed, forKey: "hoop.ai.welcomed") } }
    /// The quiet "try Hoop AI" prompt on Today, dismissed with "Not now".
    @Published var promptDismissed: Bool { didSet { UserDefaults.standard.set(promptDismissed, forKey: "hoop.ai.promptDismissed") } }

    // Ask Hoop
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isAnswering = false
    @Published var lastError: String?

    struct Message: Identifiable, Codable, Equatable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
        var role: Role
        var text: String
        var at = Date()
    }

    private var chatTask: Task<Void, Never>?
    private var authRelay: AnyCancellable?

    private init() {
        let d = UserDefaults.standard
        modelSlug = d.string(forKey: "hoop.ai.model") ?? ""
        welcomed = d.bool(forKey: "hoop.ai.welcomed")
        promptDismissed = d.bool(forKey: "hoop.ai.promptDismissed")
        if let data = UserDefaults.standard.data(forKey: Self.messagesKey),
           let saved = try? JSONDecoder().decode([Message].self, from: data) {
            messages = saved
        }
        authRelay = auth.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isConnected: Bool { auth.isSignedIn }

    /// The model every request uses: the saved choice if it's still offered, else the first listed.
    var model: String {
        if !modelSlug.isEmpty { return modelSlug }
        return models.first?.slug ?? "gpt-5"
    }

    /// The model to use, fetching ChatGPT's list first if it hasn't been loaded this launch.
    private func readyModel() async -> String {
        if models.isEmpty { await loadModels() }
        return model
    }

    var modelDisplayName: String {
        models.first(where: { $0.slug == model })?.displayName ?? model
    }

    // MARK: Connection

    func connect() async throws {
        try await auth.signIn()
        await loadModels()
    }

    func disconnect() async {
        chatTask?.cancel()
        await auth.signOut()
        welcomed = false
    }

    func loadModels() async {
        guard isConnected else { return }
        if let list = try? await HoopAIClient.models(), !list.isEmpty {
            models = list
            if !modelSlug.isEmpty, !list.contains(where: { $0.slug == modelSlug }) { modelSlug = "" }
        }
    }

    // MARK: Briefing (Today)

    struct Briefing: Codable, Equatable {
        var day: String
        var text: String
        var at: Date
    }

    @Published private(set) var briefing: Briefing? = HoopAI.loadCached(Briefing.self, key: HoopAI.briefingKey)
    @Published private(set) var briefingStreaming = ""
    @Published private(set) var isBriefing = false
    @Published var briefingError: String?

    /// Writes today's briefing, streaming it into `briefingStreaming`. Cached for the day.
    func generateBriefing(context: String, force: Bool = false) async {
        let day = Repository.localDayKey(Date())
        guard isConnected, !isBriefing else { return }
        if !force, briefing?.day == day { return }
        isBriefing = true
        briefingError = nil
        briefingStreaming = ""
        defer { isBriefing = false }
        let turns: [HoopAIClient.Turn] = [
            .init(role: .developer, text: Self.systemPrompt),
            .init(role: .user, text: """
            \(context)

            Write my briefing for today in 2 or 3 short sentences (under 60 words). Lead with what matters most \
            today (how hard to train, or how to recover), cite one or two of my numbers, and end with one \
            concrete suggestion for today. No greeting, no headings, no bullet points.
            """),
        ]
        do {
            let model = await readyModel()
            var text = ""
            for try await delta in HoopAIClient.stream(model: model, turns: turns) {
                text += delta
                briefingStreaming = text
            }
            let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw HoopAIClient.AIError.empty }
            let b = Briefing(day: day, text: final, at: Date())
            briefing = b
            Self.saveCached(b, key: Self.briefingKey)
        } catch {
            briefingError = error.localizedDescription
        }
        briefingStreaming = ""
    }

    // MARK: Sleep insight

    @Published private(set) var sleepInsights: [String: String] = HoopAI.loadCached([String: String].self, key: HoopAI.sleepKey) ?? [:]
    @Published private(set) var sleepStreaming: [String: String] = [:]

    func explainNight(key: String, context: String) async {
        guard isConnected, sleepStreaming[key] == nil else { return }
        sleepStreaming[key] = ""
        defer { sleepStreaming[key] = nil }
        let turns: [HoopAIClient.Turn] = [
            .init(role: .developer, text: Self.systemPrompt),
            .init(role: .user, text: """
            \(context)

            Explain last night's sleep in 3 or 4 short sentences (under 80 words): what went well, what held \
            the score back, and one specific thing to try tonight. Refer to my actual numbers. No headings or lists.
            """),
        ]
        do {
            let model = await readyModel()
            var text = ""
            for try await delta in HoopAIClient.stream(model: model, turns: turns) {
                text += delta
                sleepStreaming[key] = text
            }
            let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !final.isEmpty else { throw HoopAIClient.AIError.empty }
            sleepInsights[key] = final
            // Keep the last two weeks of nights.
            let kept = sleepInsights.keys.sorted().suffix(14)
            sleepInsights = sleepInsights.filter { kept.contains($0.key) }
            Self.saveCached(sleepInsights, key: Self.sleepKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Ask Hoop

    func ask(_ question: String, context: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, isConnected, !isAnswering else { return }
        lastError = nil
        messages.append(Message(role: .user, text: q))
        let replyID = UUID()
        messages.append(Message(id: replyID, role: .assistant, text: ""))
        isAnswering = true

        // The data summary rides on the system turn, so every answer reads the latest numbers.
        var turns: [HoopAIClient.Turn] = [.init(role: .developer, text: Self.systemPrompt + "\n\n" + context)]
        for m in messages.dropLast().suffix(16) where !m.text.isEmpty {
            turns.append(.init(role: m.role == .user ? .user : .assistant, text: m.text))
        }

        chatTask = Task {
            defer {
                isAnswering = false
                persistMessages()
            }
            do {
                let model = await readyModel()
                var text = ""
                for try await delta in HoopAIClient.stream(model: model, turns: turns) {
                    text += delta
                    updateMessage(replyID, text: text)
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw HoopAIClient.AIError.empty }
            } catch is CancellationError {
                removeEmpty(replyID)
            } catch {
                removeEmpty(replyID)
                lastError = error.localizedDescription
            }
        }
    }

    func stopAnswering() { chatTask?.cancel() }

    func clearConversation() {
        chatTask?.cancel()
        messages = []
        persistMessages()
    }

    private func updateMessage(_ id: UUID, text: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].text = text
    }

    private func removeEmpty(_ id: UUID) {
        if let i = messages.firstIndex(where: { $0.id == id }), messages[i].text.isEmpty { messages.remove(at: i) }
    }

    private func persistMessages() {
        let recent = Array(messages.suffix(40))
        if let data = try? JSONEncoder().encode(recent) { UserDefaults.standard.set(data, forKey: Self.messagesKey) }
    }

    // MARK: Food (Fuel)

    struct FoodEstimate: Equatable {
        var name: String
        var kcal: Int
        var protein: Double?
        var note: String?
    }

    /// Estimates a meal from a description, a photo, or both.
    func estimateFood(description: String, photo: UIImage?) async throws -> FoodEstimate {
        guard isConnected else { throw HoopAIClient.AIError.signedOut }
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        Estimate the calories and protein of this meal\(desc.isEmpty ? " in the photo" : ": \(desc)").
        Assume typical portions unless the description or photo says otherwise.
        Reply with only a JSON object, no code fences: {"name": short meal name (max 5 words), \
        "kcal": integer total calories, "protein_g": number total grams of protein, \
        "note": one short sentence on what you assumed}
        """
        let jpeg = photo.flatMap(Self.jpeg(from:))
        let turns: [HoopAIClient.Turn] = [
            .init(role: .developer, text: "You are a precise nutrition estimator. Answer with JSON only."),
            .init(role: .user, text: prompt, imageJPEG: jpeg),
        ]
        let reply = try await HoopAIClient.complete(model: await readyModel(), turns: turns)
        guard let estimate = Self.parseFood(reply) else {
            throw HoopAIClient.AIError.unsupported(String(localized: "Hoop AI couldn't read that meal. Try describing it."))
        }
        return estimate
    }

    static func parseFood(_ reply: String) -> FoodEstimate? {
        var s = reply
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") { s = String(s[start...end]) }
        guard let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let kcal = (json["kcal"] as? Double) ?? (json["kcal"] as? Int).map(Double.init) ?? Double(json["kcal"] as? String ?? "")
        guard let kcal, kcal > 0, kcal < 10_000 else { return nil }
        let protein = (json["protein_g"] as? Double) ?? (json["protein_g"] as? Int).map(Double.init)
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodEstimate(name: (name?.isEmpty == false ? name! : String(localized: "Meal")),
                            kcal: Int(kcal.rounded()), protein: protein.map { ($0 * 10).rounded() / 10 },
                            note: json["note"] as? String)
    }

    private static func jpeg(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1024
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    // MARK: Prompt

    static let systemPrompt = """
    You are Hoop, a calm, expert health and training coach inside Hoop, an unofficial iPhone companion app \
    for WHOOP straps. The person's own data is summarised below; it was computed on their iPhone from the \
    strap. Recovery is 0–100% (green 67+, yellow 34–66, red under 34). Strain is on WHOOP's 0–21 scale. \
    Sleep performance compares sleep with the sleep they needed. Be concise, warm and specific. Use their \
    real numbers and never invent data you weren't given; say when something isn't available. Give \
    practical, safe suggestions. You are not a doctor: don't diagnose, and suggest seeing a professional \
    for anything that sounds medical. Use short paragraphs; use a short list only when it clearly helps.
    """

    // MARK: Cache

    private static let messagesKey = "hoop.ai.messages"
    private static let briefingKey = "hoop.ai.briefing"
    private static let sleepKey = "hoop.ai.sleepInsights"

    private static func loadCached<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func saveCached<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Context

/// The data summary Hoop AI answers from. Built on demand, on the device, from the same numbers the
/// screens show; nothing is sent until a request is made.
@MainActor
enum HoopAIContext {
    static func build(repo: Repository, profile: ProfileStore, snapshot s: HoopTodaySnapshot) -> String {
        var lines: [String] = []
        let now = Date()
        lines.append("Today is \(now.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(now.formatted(date: .omitted, time: .shortened)).")
        lines.append("Person: \(profile.age) years old, \(profile.sex), \(Int(profile.heightCm.rounded())) cm, \(String(format: "%.1f", profile.weightKg)) kg, estimated max heart rate \(profile.hrMax) bpm.")

        switch s.charge {
        case .scored(let p): lines.append("Recovery today: \(Int(p.rounded()))%.")
        case .carried(let p, let caption): lines.append("Recovery: \(Int(p.rounded()))% (\(caption); today not scored yet).")
        case .calibrating(let n): lines.append("Recovery: still calibrating the baseline (\(n) of \(Baselines.minNightsSeed) nights).")
        case .noData: lines.append("Recovery: no score yet.")
        }
        if let strain = s.strain {
            lines.append("Strain so far today: \(String(format: "%.1f", UnitFormatter.effortValue(strain, scale: .whoop))) of 21.")
        }
        if let m = s.sleepMinutes {
            var sleep = "Last night: \(hm(m)) asleep"
            if let need = s.sleepNeedMinutes { sleep += " of \(hm(need)) needed" }
            if let score = s.sleepScore { sleep += ", sleep performance \(Int(score.rounded()))%" }
            if let d = repo.today {
                let stages = [("deep", d.deepMin), ("REM", d.remMin), ("light", d.lightMin)]
                    .compactMap { name, v in v.map { "\(name) \(hm($0))" } }
                if !stages.isEmpty { sleep += " (\(stages.joined(separator: ", ")))" }
                if let e = d.efficiency { sleep += ", efficiency \(Int((e <= 1 ? e * 100 : e).rounded()))%" }
            }
            lines.append(sleep + ".")
        } else {
            lines.append("Last night: no sleep recorded.")
        }
        var vitals: [String] = []
        if let v = s.hrv { vitals.append("HRV \(Int(v.rounded())) ms") }
        if let v = s.restingHr { vitals.append("resting heart rate \(Int(v.rounded())) bpm") }
        if let v = s.respRate { vitals.append("respiratory rate \(String(format: "%.1f", v)) per min") }
        if let v = s.spo2 { vitals.append("blood oxygen \(Int(v.rounded()))%") }
        if let v = s.skinTempDev { vitals.append("skin temperature \(String(format: "%+.1f", v)) °C vs baseline") }
        if !vitals.isEmpty { lines.append("Overnight vitals: \(vitals.joined(separator: ", ")).") }
        var activity: [String] = []
        if let v = s.steps { activity.append("\(Int(v.rounded())) steps") }
        if let v = s.totalKcal { activity.append("about \(Int(v.rounded())) kcal burned") }
        if let range = s.hrCurveRange { activity.append("heart rate \(Int(range.lowerBound))–\(Int(range.upperBound)) bpm") }
        if !activity.isEmpty { lines.append("Today so far: \(activity.joined(separator: ", ")).") }

        // Recent history, newest last.
        let recent = repo.days.suffix(14)
        if !recent.isEmpty {
            lines.append("")
            lines.append("Last \(recent.count) days (date | recovery % | strain /21 | sleep h | HRV ms | resting HR):")
            for d in recent {
                let rec = d.recovery.map { "\(Int($0.rounded()))" } ?? "-"
                let strain = d.strain.map { String(format: "%.1f", UnitFormatter.effortValue($0, scale: .whoop)) } ?? "-"
                let sleep = d.totalSleepMin.map { String(format: "%.1f", $0 / 60) } ?? "-"
                let hrv = d.avgHrv.map { "\(Int($0.rounded()))" } ?? "-"
                let rhr = d.restingHr.map(String.init) ?? "-"
                lines.append("\(d.day) | \(rec) | \(strain) | \(sleep) | \(hrv) | \(rhr)")
            }
        }

        // Fuel, when set up.
        let plan = CutPlanStore.shared
        if plan.configured {
            let key = Repository.localDayKey(now)
            let male = profile.sex != "female"
            let est = plan.estimatedKg(beforeDay: key, heightCm: profile.heightCm, age: profile.age, male: male).kg
            let b = plan.budget(weightKg: est, heightCm: profile.heightCm, age: profile.age, male: male,
                                activeKcal: s.activeKcal ?? 0, eaten: plan.eaten(day: key))
            lines.append("")
            lines.append("Weight goal: \(String(format: "%.1f", plan.goalKg)) kg by \(plan.targetDate.formatted(date: .abbreviated, time: .omitted)); estimated weight now \(String(format: "%.1f", est)) kg.")
            lines.append("Food today: \(Int(b.eaten.rounded())) of \(Int(b.allowance.rounded())) kcal allowance eaten; protein \(Int(plan.protein(day: key).rounded())) of \(Int(plan.proteinTarget.rounded())) g.")
            let foods = plan.entries(day: key).map { "\($0.name) \($0.kcal) kcal" }
            if !foods.isEmpty { lines.append("Logged today: \(foods.joined(separator: "; ")).") }
        }
        return lines.joined(separator: "\n")
    }

    private static func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }
}
#endif
