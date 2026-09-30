#if os(iOS)
import Combine
import Foundation

/// Vitals the person logs by hand (blood pressure, resting heart rate, blood glucose, body temperature),
/// kept on this iPhone in UserDefaults, like `CutPlanStore`.
///
/// Weight is deliberately NOT kept here. Fuel already keeps weigh-ins (`CutPlanStore.weighIns`) and plans
/// the calorie budget and the expected weight from the latest one, so a second weight list would let the
/// two tabs show different numbers for the same scale reading. `CutPlanStore` is the single source of
/// truth: logging a weight from Vitals appends a Fuel weigh-in and updates the profile weight exactly as
/// Fuel's own sheet does (`HoopWeighIn.log`), and the Weight vital reads that list straight back.
@MainActor
final class HoopVitalsLog: ObservableObject {
    static let shared = HoopVitalsLog()

    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var kind: HoopManualVital
        /// The reading in its stored unit: bpm, mg/dL or °C; the systolic for blood pressure.
        var value: Double
        /// The diastolic, for blood pressure only.
        var value2: Double?
        var at: Date
    }

    @Published private(set) var entries: [Entry] { didSet { save() } }

    private let defaults = UserDefaults.standard
    private static let key = "hoop.vitals.log"

    private init() {
        // Decoded one entry at a time, so one unreadable entry (a kind a later version removed) can't
        // take every other reading with it.
        let decoded = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Lenient].self, from: $0) } ?? []
        entries = decoded.compactMap(\.entry)
    }

    /// Readings of one kind, oldest first.
    func entries(for kind: HoopManualVital) -> [Entry] {
        entries.filter { $0.kind == kind }.sorted { $0.at < $1.at }
    }

    /// Adds a reading. Weight goes through `HoopWeighIn.log` instead (see the type comment).
    func add(_ kind: HoopManualVital, value: Double, value2: Double? = nil, at: Date) {
        guard kind != .weight, value.isFinite, value2?.isFinite ?? true else { return }
        entries.append(Entry(kind: kind, value: value, value2: value2, at: at))
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }

    private struct Lenient: Decodable {
        let entry: Entry?
        init(from decoder: Decoder) throws { entry = try? Entry(from: decoder) }
    }
}

/// The one way Hoop logs a weight: as a Fuel weigh-in, plus the profile weight, the same two writes
/// Fuel's own weigh-in sheet makes.
enum HoopWeighIn {
    @MainActor
    static func log(kg: Double, at date: Date = Date(), plan: CutPlanStore, profile: ProfileStore) {
        plan.logWeight(kg, at: date)
        // The profile weight is "now": only the newest weigh-in may move it.
        if plan.weighIns.max(by: { $0.at < $1.at })?.kg == kg { profile.weightKg = kg }
    }
}

/// Which vitals Today shows, and in what order: a comma-separated list of catalog ids in UserDefaults,
/// read with `@AppStorage(HoopVitalsPrefs.shownKey)`. Unset means the defaults; an empty string means
/// the person hid them all.
enum HoopVitalsPrefs {
    static let shownKey = "hoop.vitals.shown"
    /// The blood-glucose unit last chosen in the log sheet (`HoopGlucoseUnit` raw value).
    static let glucoseUnitKey = "hoop.vitals.glucoseUnit"

    static var defaultRaw: String { encode(HoopVitalCatalog.defaultIDs) }

    /// Ids in order, dropping duplicates and any id the catalog no longer knows.
    static func decode(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { HoopVitalCatalog.vital(id: $0) != nil && seen.insert($0).inserted }
    }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }

    /// Adds a vital to the end of Today's list if it isn't there yet. Writes UserDefaults directly, so it
    /// is safe after the view that asked has gone; every `@AppStorage(shownKey)` reader updates.
    static func show(_ id: String) {
        let defaults = UserDefaults.standard
        var ids = decode(defaults.string(forKey: shownKey) ?? defaultRaw)
        guard !ids.contains(id), HoopVitalCatalog.vital(id: id) != nil else { return }
        ids.append(id)
        defaults.set(encode(ids), forKey: shownKey)
    }
}
#endif
