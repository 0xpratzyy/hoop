#if os(iOS)
import SwiftUI
import StrandAnalytics

// MARK: - What a vital is
//
// Every vital Hoop can show is either a NOOP catalog metric (`MetricCatalog.all`, read through the same
// `Repository.exploreSeries` call NOOP's Metric Explorer uses, so the numbers match NOOP's) or a reading
// the person types in because the strap can't take it. Both get the same row, chart and detail.

/// A vital the person measures themselves and logs by hand.
enum HoopManualVital: String, CaseIterable, Identifiable, Codable, Hashable {
    case weight, bloodPressure, restingHeartRate, bloodGlucose, bodyTemperature

    var id: String { rawValue }

    /// Catalog id, namespaced so it can never collide with a NOOP metric id (`source:key`).
    var vitalID: String { "manual:" + rawValue }

    var title: String {
        switch self {
        case .weight: return String(localized: "Weight")
        case .bloodPressure: return String(localized: "Blood pressure")
        case .restingHeartRate: return String(localized: "Resting heart rate (manual)")
        case .bloodGlucose: return String(localized: "Blood glucose")
        case .bodyTemperature: return String(localized: "Body temperature")
        }
    }

    /// The name in the log sheet's picker, where "(manual)" would be redundant.
    var pickerTitle: String {
        self == .restingHeartRate ? String(localized: "Resting heart rate") : title
    }

    var logLabel: String {
        switch self {
        case .weight: return String(localized: "Log weight")
        case .bloodPressure: return String(localized: "Log blood pressure")
        case .restingHeartRate: return String(localized: "Log resting heart rate")
        case .bloodGlucose: return String(localized: "Log blood glucose")
        case .bodyTemperature: return String(localized: "Log body temperature")
        }
    }
}

/// The groups the editor lists vitals under: NOOP's categories in plain words (NOOP says Charge, Rest,
/// Effort and Health), plus the person's own logs.
enum HoopVitalCategory: String, CaseIterable, Identifiable {
    case heart, recovery, sleep, activity, body, logged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heart: return String(localized: "Heart")
        case .recovery: return String(localized: "Recovery")
        case .sleep: return String(localized: "Sleep")
        case .activity: return String(localized: "Activity")
        case .body: return String(localized: "Body")
        case .logged: return String(localized: "Logged by you")
        }
    }

    /// NOOP's catalog category, which stays an English identifier, mapped to Hoop's group. Nutrition and
    /// Mind are left out: food lives in Fuel and mood is a check-in, not a vital.
    static func from(noop category: String) -> HoopVitalCategory? {
        switch category {
        case "Heart": return .heart
        case "Charge": return .recovery
        case "Rest": return .sleep
        case "Effort": return .activity
        case "Health": return .body
        default: return nil
        }
    }
}

/// How often a vital produces a reading, which decides how its row states "latest" honestly.
enum HoopVitalCadence: Hashable {
    /// One reading per night, keyed on the wake day. A reading from an earlier night is carried and says so.
    case overnight
    /// One value per calendar day that only settles once the day ends (strain, minutes in zones).
    case dailyTotal
    /// One value per calendar day (average or max heart rate, day stress).
    case daily
    /// Occasional readings: weekly estimates, imports and anything logged by hand. The row shows the last
    /// few readings and how old the latest one is, rather than a calendar week.
    case occasional
}

/// How a row puts a change into words.
enum HoopVitalDelta: Hashable {
    /// As a percentage ("↑ 6%"), for HRV, whose scale differs a lot between people.
    case relative
    /// In the vital's own unit ("↑ 3 bpm", "↓ 0.4 kg", "↑ 2 pts").
    case absolute
}

struct HoopVital: Identifiable, Hashable {
    enum Source: Hashable {
        case metric(MetricDescriptor)
        case manual(HoopManualVital)
    }

    let id: String
    let title: String
    let category: HoopVitalCategory
    let source: Source
    let cadence: HoopVitalCadence
    let delta: HoopVitalDelta

    var metric: MetricDescriptor? {
        if case .metric(let m) = source { return m }
        return nil
    }

    var manual: HoopManualVital? {
        if case .manual(let k) = source { return k }
        return nil
    }

    /// NOOP's metric key, or the manual kind.
    var key: String { metric?.key ?? manual?.rawValue ?? id }

    /// Held in minutes and shown as hours and minutes.
    var isMinutes: Bool { metric?.unit == "min" }

    /// Where the numbers come from, in the reader's words.
    var sourceLabel: String {
        switch source {
        case .manual(let kind):
            return kind == .weight
                ? String(localized: "Logged by you, shared with Fuel's weigh-ins")
                : String(localized: "Logged by you, kept on this iPhone")
        case .metric(let m):
            switch m.source {
            case "apple-health": return String(localized: "From Apple Health")
            case "xiaomi-band": return String(localized: "From your Mi Band import")
            default:
                return m.key == "vo2max_est" || m.key == "fitness_age" || m.key == "body_age" || m.key == "vitality"
                    ? String(localized: "Estimated on this iPhone from your strap data")
                    : String(localized: "From your strap, computed on this iPhone")
            }
        }
    }
}

// MARK: - Catalog

enum HoopVitalCatalog {
    /// What Today shows until the person edits the list.
    static let defaultIDs = [
        "my-whoop:hrv", "my-whoop:rhr", "my-whoop:resp_rate",
        "my-whoop:spo2", "my-whoop:skin_temp", "my-whoop:vo2max_est",
    ]

    /// Steps and calories already have a home in Today's Activity section, each read through its own
    /// resolver; listing them here as well would put two readouts of one fact on the same screen.
    private static let excludedKeys: Set<String> = ["steps", "steps_est", "energy_kcal", "active_kcal"]

    /// Every vital, in catalog order: NOOP's metrics first, then the ones logged by hand.
    static let all: [HoopVital] = {
        var out: [HoopVital] = []
        var seen = Set<String>()
        for m in MetricCatalog.all where !excludedKeys.contains(m.key) {
            guard let category = HoopVitalCategory.from(noop: m.category), seen.insert(m.id).inserted else { continue }
            let spec = spec(for: m.key)
            out.append(HoopVital(id: m.id, title: title(for: m, base: spec.title), category: category,
                                 source: .metric(m), cadence: spec.cadence, delta: spec.delta))
        }
        for kind in HoopManualVital.allCases {
            out.append(HoopVital(id: kind.vitalID, title: kind.title, category: .logged, source: .manual(kind),
                                 cadence: .occasional, delta: .absolute))
        }
        return out
    }()

    private static let byID: [String: HoopVital] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func vital(id: String) -> HoopVital? { byID[id] }

    static func vital(for kind: HoopManualVital) -> HoopVital {
        byID[kind.vitalID] ?? HoopVital(id: kind.vitalID, title: kind.title, category: .logged,
                                        source: .manual(kind), cadence: .occasional, delta: .absolute)
    }

    /// Sources a person may never have used (a Mi Band import) are only listed once they hold data.
    static func listedOnlyWithData(_ vital: HoopVital) -> Bool { vital.metric?.source == "xiaomi-band" }

    private struct Spec {
        var title: String?
        var cadence: HoopVitalCadence
        var delta: HoopVitalDelta = .absolute
    }

    /// Hoop's sentence-case name and reading cadence for each NOOP key. Unknown keys keep NOOP's title.
    private static func spec(for key: String) -> Spec {
        switch key {
        case "avg_hr": return Spec(title: String(localized: "Average heart rate"), cadence: .daily)
        case "max_hr": return Spec(title: String(localized: "Max heart rate"), cadence: .daily)
        case "vo2max": return Spec(title: String(localized: "VO₂ max"), cadence: .occasional)
        case "vo2max_est": return Spec(title: String(localized: "VO₂ max (estimated)"), cadence: .occasional)
        case "fitness_age": return Spec(title: String(localized: "Fitness age"), cadence: .occasional)
        case "vitality": return Spec(title: String(localized: "Vitality"), cadence: .occasional)
        case "body_age": return Spec(title: String(localized: "Body age"), cadence: .occasional)
        case "recovery": return Spec(title: String(localized: "Recovery"), cadence: .overnight)
        case "hrv": return Spec(title: "HRV", cadence: .overnight, delta: .relative)
        case "rhr": return Spec(title: String(localized: "Resting heart rate"), cadence: .overnight)
        case "resp_rate": return Spec(title: String(localized: "Respiratory rate"), cadence: .overnight)
        case "spo2": return Spec(title: String(localized: "Blood oxygen"), cadence: .overnight)
        case "skin_temp": return Spec(title: String(localized: "Skin temperature"), cadence: .overnight)
        case "sleep_performance": return Spec(title: String(localized: "Sleep performance"), cadence: .overnight)
        case "in_bed_min": return Spec(title: String(localized: "Time in bed"), cadence: .overnight)
        case "sleep_total_min": return Spec(title: String(localized: "Time asleep"), cadence: .overnight)
        case "hours_vs_needed_pct": return Spec(title: String(localized: "Sleep vs need"), cadence: .overnight)
        case "sleep_consistency": return Spec(title: String(localized: "Sleep consistency"), cadence: .overnight)
        case "restorative_pct": return Spec(title: String(localized: "Restorative sleep"), cadence: .overnight)
        case "restorative_min": return Spec(title: String(localized: "Restorative sleep time"), cadence: .overnight)
        case "sleep_efficiency": return Spec(title: String(localized: "Sleep efficiency"), cadence: .overnight)
        case "sleep_deep_min": return Spec(title: String(localized: "Deep sleep"), cadence: .overnight)
        case "sleep_rem_min": return Spec(title: String(localized: "REM sleep"), cadence: .overnight)
        case "sleep_light_min": return Spec(title: String(localized: "Light sleep"), cadence: .overnight)
        case "sleep_need_min": return Spec(title: String(localized: "Sleep need"), cadence: .overnight)
        case "sleep_debt_min": return Spec(title: String(localized: "Sleep debt"), cadence: .overnight)
        case "sleep_score": return Spec(title: String(localized: "Sleep score"), cadence: .overnight)
        case "strain": return Spec(title: String(localized: "Strain"), cadence: .dailyTotal)
        case "hr_zones13_min": return Spec(title: String(localized: "Time in zones 1–3"), cadence: .dailyTotal)
        case "hr_zones45_min": return Spec(title: String(localized: "Time in zones 4–5"), cadence: .dailyTotal)
        case "hr_zones_all_min": return Spec(title: String(localized: "Time in heart rate zones"), cadence: .dailyTotal)
        case "strength_min": return Spec(title: String(localized: "Strength training time"), cadence: .dailyTotal)
        case "intensity_min": return Spec(title: String(localized: "Intensity minutes"), cadence: .dailyTotal)
        case "weight": return Spec(title: String(localized: "Weight"), cadence: .occasional)
        case "body_fat": return Spec(title: String(localized: "Body fat"), cadence: .occasional)
        case "lean_mass": return Spec(title: String(localized: "Lean body mass"), cadence: .occasional)
        case "bmi": return Spec(title: "BMI", cadence: .occasional)
        case "stress": return Spec(title: String(localized: "Day stress"), cadence: .daily)
        default: return Spec(title: nil, cadence: .daily)
        }
    }

    /// Titles stay unique across the whole list: the Mi Band copies, and the two Apple Health metrics
    /// that share a name with another vital, carry their source.
    private static func title(for m: MetricDescriptor, base: String?) -> String {
        let name = base ?? m.title
        switch m.source {
        case "xiaomi-band": return String(localized: "\(name) (Mi Band)")
        case "apple-health" where m.key == "vo2max" || m.key == "weight":
            return String(localized: "\(name) (Apple Health)")
        default: return name
        }
    }
}

// MARK: - Units

/// Blood glucose display unit. Readings are stored in mg/dL.
enum HoopGlucoseUnit: String, CaseIterable, Identifiable {
    case mgdl, mmol

    var id: String { rawValue }
    var label: String { self == .mgdl ? "mg/dL" : "mmol/L" }

    /// mg/dL in one mmol/L of glucose (molar mass 180.16 g/mol).
    static let mgPerMmol = 18.016

    /// Regions whose meters read mmol/L; mg/dL elsewhere. Only the first default: the log sheet has a
    /// picker, and the choice is remembered.
    static var regionalDefault: HoopGlucoseUnit {
        let mmolRegions: Set<String> = ["GB", "IE", "CA", "AU", "NZ", "ZA", "NL", "SE", "NO", "DK", "FI", "CN", "HK", "RU"]
        return mmolRegions.contains(Locale.current.region?.identifier ?? "") ? .mmol : .mgdl
    }
}

/// The reader's display units, resolved from the same preferences the rest of Hoop and NOOP read.
struct HoopVitalUnits: Equatable {
    var system: UnitSystem
    var temperature: TemperatureUnit
    var effortScale: EffortScale
    var glucose: HoopGlucoseUnit

    init(systemRaw: String, temperatureRaw: String, effortRaw: String, glucoseRaw: String) {
        system = UnitSystem(rawValue: systemRaw) ?? .metric
        temperature = UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
        // Hoop reads strain on WHOOP's 0–21 axis unless the reader picked 0–100 (see HoopTodayView).
        effortScale = EffortScale(rawValue: effortRaw) ?? .whoop
        glucose = HoopGlucoseUnit(rawValue: glucoseRaw) ?? .regionalDefault
    }

    var fahrenheit: Bool { temperature == .fahrenheit }
}

/// A formatted reading: the number, its unit, and the same thing spelled out for VoiceOver.
struct HoopVitalText: Equatable {
    var value: String
    var unit: String
    var spoken: String

    static let none = HoopVitalText(value: HoopFormat.dash, unit: "", spoken: String(localized: "no reading"))
}

extension HoopVital {
    /// A stored value on the reader's scale: kg → lb, °C → °F, strain 0–100 → the chosen strain scale,
    /// mg/dL → mmol/L. Rows, charts and stats all read on this scale.
    func display(_ stored: Double, _ u: HoopVitalUnits) -> Double {
        switch key {
        case "strain": return UnitFormatter.effortValue(stored, scale: u.effortScale)
        case "weight", "lean_mass": return u.system == .imperial ? UnitFormatter.kgToPounds(stored) : stored
        case "skin_temp":
            // Bimodal field (#622): an imported absolute takes the full C→F; a deviation only scales.
            guard u.fahrenheit else { return stored }
            return SkinTempDisplay.kind(of: stored) == .absolute
                ? UnitFormatter.celsiusToFahrenheit(stored) : UnitFormatter.celsiusDeltaToFahrenheit(stored)
        case HoopManualVital.bodyTemperature.rawValue:
            return u.fahrenheit ? UnitFormatter.celsiusToFahrenheit(stored) : stored
        case HoopManualVital.bloodGlucose.rawValue:
            return u.glucose == .mmol ? stored / HoopGlucoseUnit.mgPerMmol : stored
        default: return stored
        }
    }

    /// The inverse of `display`, for the log sheet: a typed value on the reader's scale → the stored unit.
    func stored(fromDisplay n: Double, _ u: HoopVitalUnits) -> Double {
        switch key {
        case "weight", "lean_mass": return u.system == .imperial ? n / UnitFormatter.poundsPerKilogram : n
        case HoopManualVital.bodyTemperature.rawValue: return u.fahrenheit ? (n - 32) * 5 / 9 : n
        case HoopManualVital.bloodGlucose.rawValue: return u.glucose == .mmol ? n * HoopGlucoseUnit.mgPerMmol : n
        default: return n
        }
    }

    /// A skin-temperature reading held as a signed difference from the personal baseline.
    func isDeviation(_ stored: Double) -> Bool {
        key == "skin_temp" && SkinTempDisplay.kind(of: stored) == .deviation
    }

    func decimals(_ u: HoopVitalUnits) -> Int {
        if let m = metric {
            if m.key == "strain" || m.unit == "kg" { return 1 }
            return m.decimals
        }
        switch manual {
        case .weight, .bodyTemperature: return 1
        case .bloodGlucose: return u.glucose == .mmol ? 1 : 0
        default: return 0
        }
    }

    /// The unit beside a number. `compact` drops long units that would crowd a row (VO₂ max).
    func unitLabel(_ u: HoopVitalUnits, compact: Bool = true) -> String {
        if let m = metric {
            switch m.key {
            case "strain": return String(localized: "of \(UnitFormatter.effortScaleMax(u.effortScale))")
            case "skin_temp": return UnitFormatter.temperatureUnit(u.temperature)
            case "vo2max", "vo2max_est": return compact ? "" : "ml/kg/min"
            default: break
            }
            switch m.unit {
            case "kg": return UnitFormatter.massUnit(u.system)
            case "min": return ""
            case "/3": return String(localized: "of 3")
            case "/5": return String(localized: "of 5")
            case "/100": return String(localized: "of 100")
            default: return m.unit
            }
        }
        switch manual {
        case .weight: return UnitFormatter.massUnit(u.system)
        case .bloodPressure: return "mmHg"
        case .restingHeartRate: return "bpm"
        case .bloodGlucose: return u.glucose.label
        case .bodyTemperature: return UnitFormatter.temperatureUnit(u.temperature)
        case nil: return ""
        }
    }

    /// The unit spelled out for VoiceOver.
    func spokenUnit(_ u: HoopVitalUnits) -> String {
        if key == "vo2max" || key == "vo2max_est" { return String(localized: "millilitres per kilogram per minute") }
        switch unitLabel(u) {
        case "ms": return String(localized: "milliseconds")
        case "bpm": return String(localized: "beats per minute")
        case "rpm": return String(localized: "breaths per minute")
        case "%": return String(localized: "percent")
        case "°C": return String(localized: "degrees Celsius")
        case "°F": return String(localized: "degrees Fahrenheit")
        case "kg": return String(localized: "kilograms")
        case "lb": return String(localized: "pounds")
        case "mmHg": return String(localized: "millimetres of mercury")
        case "mg/dL": return String(localized: "milligrams per decilitre")
        case "mmol/L": return String(localized: "millimoles per litre")
        case "yrs": return String(localized: "years")
        case let other: return other
        }
    }

    /// A stored reading, formatted on the reader's scale. `diastolic` is blood pressure's second number.
    func text(_ stored: Double, diastolic: Double? = nil, _ u: HoopVitalUnits) -> HoopVitalText {
        if manual == .bloodPressure {
            let sys = Int(stored.rounded())
            guard let dia = diastolic.map({ Int($0.rounded()) }) else {
                return HoopVitalText(value: "\(sys)", unit: "mmHg", spoken: "\(sys) " + spokenUnit(u))
            }
            return HoopVitalText(value: "\(sys)/\(dia)", unit: "mmHg",
                                 spoken: String(localized: "\(sys) over \(dia) millimetres of mercury"))
        }
        return formatted(display: display(stored, u), signed: isDeviation(stored), u)
    }

    /// A number already on the reader's scale (an average, an axis tick), formatted with its unit.
    func formatted(display n: Double, signed: Bool = false, _ u: HoopVitalUnits) -> HoopVitalText {
        guard n.isFinite else { return .none }
        if isMinutes {
            return HoopVitalText(value: Self.minutesText(n), unit: "", spoken: Self.minutesSpoken(n))
        }
        let value = Self.decimal(n, decimals(u), signed: signed)
        let unit = unitLabel(u)
        let spokenUnit = spokenUnit(u)
        return HoopVitalText(value: value, unit: unit, spoken: spokenUnit.isEmpty ? value : "\(value) \(spokenUnit)")
    }

    /// The size of a change, unsigned, with its unit ("0.4 kg", "3 bpm", "12m", "2 pts").
    func deltaText(_ magnitude: Double, _ u: HoopVitalUnits) -> (text: String, spoken: String) {
        if isMinutes { return (Self.minutesText(magnitude), Self.minutesSpoken(magnitude)) }
        let n = Self.decimal(magnitude, decimals(u))
        let unit = unitLabel(u)
        // Scores out of a maximum ("of 21") change by plain points.
        let outOf = key == "strain" || ["/3", "/5", "/100"].contains(metric?.unit ?? "")
        if unit.isEmpty || outOf { return (n, n) }
        switch unit {
        case "%": return (String(localized: "\(n) pts"), String(localized: "\(n) percentage points"))
        case "°C", "°F": return ("\(n)°", String(localized: "\(n) degrees"))
        default: return ("\(n) \(unit)", "\(n) \(spokenUnit(u))")
        }
    }

    /// True when a change is too small to show at this vital's precision (under half a displayed step).
    func roundsToZero(_ change: Double, _ u: HoopVitalUnits) -> Bool {
        if isMinutes { return abs(change) < 0.5 }
        return abs(change) < 0.5 * pow(10, -Double(decimals(u)))
    }

    // MARK: Number formatting

    /// A locale-formatted decimal. A value that rounds to zero loses its sign, so "−0.0" never shows.
    static func decimal(_ v: Double, _ decimals: Int, signed: Bool = false) -> String {
        let scale = pow(10, Double(decimals))
        var rounded = (v * scale).rounded() / scale
        if rounded == 0 { rounded = 0 }
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(decimals))
            .sign(strategy: signed ? .always(includingZero: false) : .automatic)
        return rounded.formatted(style)
    }

    /// "7h 12m", "45m", or "0m" for a real zero (a sleep debt of nothing is a reading, not a gap).
    static func minutesText(_ minutes: Double) -> String {
        guard minutes.isFinite else { return HoopFormat.dash }
        let m = Int(minutes.rounded())
        return m <= 0 ? "0m" : HoopFormat.hoursMinutes(Double(m))
    }

    static func minutesSpoken(_ minutes: Double) -> String {
        guard minutes.isFinite else { return String(localized: "no reading") }
        let m = max(Int(minutes.rounded()), 0)
        return Duration.seconds(m * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
#endif
