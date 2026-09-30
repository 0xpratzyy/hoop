#if os(iOS)
import SwiftUI
import StrandAnalytics

/// One reading behind a row, chart or stat.
struct HoopVitalPoint: Identifiable, Hashable {
    let id: String
    /// Local `yyyy-MM-dd`, keyed the same way `DailyMetric.day` is.
    let day: String
    /// Local midnight for a day-keyed series; the moment itself for a logged reading.
    let date: Date
    /// In the stored unit (`HoopVital.display` puts it on the reader's scale).
    let value: Double
    /// The diastolic, for blood pressure.
    var value2: Double? = nil
}

// MARK: - Dates

enum HoopVitalDates {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local midnight of a `yyyy-MM-dd` key.
    static func date(_ day: String) -> Date? { parser.date(from: day) }

    static func key(_ date: Date) -> String { Repository.localDayKey(date) }

    /// The key `n` calendar days before `day`.
    static func key(_ day: String, minus n: Int) -> String {
        guard let d = date(day), let back = Calendar.current.date(byAdding: .day, value: -n, to: d) else { return day }
        return key(back)
    }

    /// Whole calendar days from `from` to `to` (0 on the same day).
    static func days(from: String, to: String) -> Int {
        guard let a = date(from), let b = date(to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// The seven local calendar days ending on `today`, oldest first (the same week the snapshot uses).
    static func weekKeys(endingOn today: String) -> [String] {
        (0..<7).reversed().map { key(today, minus: $0) }
    }

    /// "12 Sep" in the reader's locale.
    static func short(_ day: String) -> String {
        date(day)?.formatted(.dateTime.day().month(.abbreviated)) ?? day
    }

    /// "Today", "Yesterday", a weekday inside the week, else "12 Sep", with its spoken form.
    static func relative(_ day: String, today: String) -> (text: String, spoken: String) {
        let age = days(from: day, to: today)
        if age <= 0 { let t = String(localized: "Today"); return (t, t) }
        if age == 1 { let t = String(localized: "Yesterday"); return (t, t) }
        guard let d = date(day) else { return (day, day) }
        if age < 7 { return (d.formatted(.dateTime.weekday(.abbreviated)), d.formatted(.dateTime.weekday(.wide))) }
        return (short(day), d.formatted(.dateTime.day().month(.wide)))
    }
}

// MARK: - Loading

@MainActor
enum HoopVitalsLoader {
    /// History behind a row: the 90-day chart, with room to find an occasional reading's latest value.
    nonisolated static let lookbackDays = 400

    /// A NOOP metric's daily series through `Repository.exploreSeries`, the read NOOP's Metric Explorer
    /// uses (imported over computed over the merged daily columns, one skin-temperature scale), so every
    /// number here is the number NOOP shows.
    static func metricPoints(_ m: MetricDescriptor, repo: Repository, days: Int = lookbackDays) async -> [HoopVitalPoint] {
        let rows = await repo.exploreSeries(key: m.key, source: m.source, days: days)
        return rows.compactMap { row in
            guard row.value.isFinite, let date = HoopVitalDates.date(row.day) else { return nil }
            // Some imports store sleep efficiency as a 0–1 fraction; every row reads as a percent, as in
            // Hoop AI's summary.
            let value = m.key == "sleep_efficiency" && row.value <= 1 ? row.value * 100 : row.value
            return HoopVitalPoint(id: row.day, day: row.day, date: date, value: value)
        }
    }

    /// Readings logged by hand, oldest first. Weight is Fuel's weigh-in list itself (see `HoopVitalsLog`).
    static func manualPoints(_ kind: HoopManualVital, log: HoopVitalsLog, plan: CutPlanStore) -> [HoopVitalPoint] {
        switch kind {
        case .weight:
            return plan.weighIns.sorted { $0.at < $1.at }.map {
                HoopVitalPoint(id: $0.id.uuidString, day: HoopVitalDates.key($0.at), date: $0.at, value: $0.kg)
            }
        default:
            return log.entries(for: kind).map {
                HoopVitalPoint(id: $0.id.uuidString, day: HoopVitalDates.key($0.at), date: $0.at,
                               value: $0.value, value2: $0.value2)
            }
        }
    }
}

// MARK: - Resolving what a row says

/// Everything one row (and the top of its detail screen) shows, resolved in one place so the row and the
/// detail can never disagree.
struct HoopVitalSummary {
    let vital: HoopVital
    /// The reading the row leads with; nil shows a dash, never a stand-in number.
    let latest: HoopVitalPoint?
    let text: HoopVitalText
    /// Reader-scale values for the sparkline, oldest first: the last seven days (nil where a day has no
    /// reading), or for an occasional vital its last seven readings.
    let spark: [Double?]
    let caption: String
    let spokenCaption: String
    /// The reading is from an earlier night or day than today, and the caption says when.
    let carried: Bool
}

@MainActor
enum HoopVitalResolver {
    static func summary(_ vital: HoopVital, points raw: [HoopVitalPoint], snapshot s: HoopTodaySnapshot,
                        units u: HoopVitalUnits, now: Date = Date()) -> HoopVitalSummary {
        let (todayKey, localToday) = keys(s, now)
        // Future-clock guard: a stray row dated after today (a bad-clock strap) is never "latest".
        let points = raw.filter { $0.day <= max(todayKey, localToday) }

        let latest: HoopVitalPoint?
        switch pinned(vital, s, localToday: localToday) {
        case .reading(let p): latest = p
        case .notPinned: latest = points.last
        }

        let carried: Bool
        switch vital.cadence {
        case .overnight: carried = latest.map { $0.day < todayKey } ?? false
        case .daily, .dailyTotal: carried = latest.map { $0.day < localToday } ?? false
        case .occasional: carried = false
        }

        let spark: [Double?]
        var priorWeek: [Double] = []
        if vital.cadence == .occasional {
            spark = points.suffix(7).map { vital.display($0.value, u) }
        } else {
            var byDay = Dictionary(points.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
            // The row's own number is the week's last dot, even where Today resolved it (live strain).
            if let latest { byDay[latest.day] = latest.value }
            if vital.key == "skin_temp", let latest {
                // Never set a deviation beside an imported absolute (#622): keep the latest's scale only.
                let kind = SkinTempDisplay.kind(of: latest.value)
                byDay = byDay.filter { SkinTempDisplay.kind(of: $0.value) == kind }
            }
            let week = HoopVitalDates.weekKeys(endingOn: localToday)
            spark = week.map { byDay[$0].map { vital.display($0, u) } }
            priorWeek = week.filter { $0 != latest?.day }.compactMap { byDay[$0].map { vital.display($0, u) } }
        }

        let caption = captionFor(vital, latest: latest, carried: carried, points: points, priorWeek: priorWeek,
                                 s: s, u: u, todayKey: todayKey, localToday: localToday)
        return HoopVitalSummary(vital: vital, latest: latest,
                                text: latest.map { vital.text($0.value, diastolic: $0.value2, u) } ?? .none,
                                spark: spark, caption: caption.text, spokenCaption: caption.spoken,
                                carried: carried)
    }

    /// The readings a chart plots over the trailing `days` calendar days, oldest first. The row's own
    /// reading stands in for its day, so the chart ends on the number at the top of the screen.
    static func chartPoints(_ raw: [HoopVitalPoint], summary: HoopVitalSummary, days: Int,
                            snapshot s: HoopTodaySnapshot, now: Date = Date()) -> [HoopVitalPoint] {
        let (todayKey, localToday) = keys(s, now)
        let start = HoopVitalDates.key(localToday, minus: days - 1)
        var points = raw.filter { $0.day >= start && $0.day <= max(todayKey, localToday) }
        if let latest = summary.latest, summary.vital.cadence != .occasional, latest.day >= start {
            points.removeAll { $0.day == latest.day }
            points.append(latest)
        }
        if summary.vital.key == "skin_temp", let kind = summary.latest.map({ SkinTempDisplay.kind(of: $0.value) }) {
            points = points.filter { SkinTempDisplay.kind(of: $0.value) == kind }
        }
        return points.sorted { $0.date < $1.date }
    }

    /// Today's row key (as the snapshot resolved it) and the local calendar day.
    private static func keys(_ s: HoopTodaySnapshot, _ now: Date) -> (today: String, local: String) {
        (s.todayKey.isEmpty ? Repository.logicalDayKey(now) : s.todayKey, Repository.localDayKey(now))
    }

    private enum Pinned {
        case reading(HoopVitalPoint?)
        case notPinned
    }

    /// Today's snapshot's own answer for the vitals and scores it resolves (NOOP's carry rules, the live
    /// strain, the fresh-only sleep score). Taking them from there keeps this section in step with the
    /// rest of Today, and with what Hoop AI is told.
    private static func pinned(_ v: HoopVital, _ s: HoopTodaySnapshot, localToday: String) -> Pinned {
        guard let m = v.metric, m.source == Repository.whoopSource else { return .notPinned }
        func reading(_ value: Double?, _ day: String?) -> Pinned {
            guard let value, value.isFinite, let day, let date = HoopVitalDates.date(day) else { return .reading(nil) }
            return .reading(HoopVitalPoint(id: day, day: day, date: date, value: value))
        }
        switch m.key {
        case "hrv": return reading(s.hrv, s.hrvDay)
        case "rhr": return reading(s.restingHr, s.restingHrDay)
        case "resp_rate": return reading(s.respRate, s.respRateDay)
        case "spo2": return reading(s.spo2, s.spo2Day)
        case "skin_temp": return reading(s.skinTempDev, s.skinTempDay)
        case "recovery": return reading(s.charge.pct, s.chargeDay)
        case "strain": return reading(s.strain, localToday)
        case "sleep_performance": return reading(s.sleepScore, s.sleepScoreDay)
        default: return .notPinned
        }
    }

    // MARK: Captions

    private static func captionFor(_ v: HoopVital, latest: HoopVitalPoint?, carried: Bool,
                                   points: [HoopVitalPoint], priorWeek: [Double], s: HoopTodaySnapshot,
                                   u: HoopVitalUnits, todayKey: String,
                                   localToday: String) -> (text: String, spoken: String) {
        func same(_ t: String) -> (text: String, spoken: String) { (t, t) }

        guard let latest else {
            if v.key == "recovery", case .calibrating(let n) = s.charge {
                let seed = Baselines.minNightsSeed
                return same(String(localized: "Calibrating · \(min(n, seed)) of \(seed) nights"))
            }
            if v.key == "strain" { return same(String(localized: "Builds as you move today")) }
            if v.manual != nil { return same(String(localized: "Not logged yet")) }
            // History exists but nothing current: Today's carry rules turned an old value down.
            return same(points.isEmpty ? String(localized: "No data yet") : String(localized: "No recent reading"))
        }
        if v.cadence == .occasional { return occasional(v, latest: latest, points: points, u: u, localToday: localToday) }
        if carried {
            if v.key == "recovery", case .carried(_, let caption) = s.charge { return same(caption) }
            if v.cadence == .overnight {
                return same(TodayView.carriedCaption(priorDayKey: latest.day, todayKey: todayKey))
            }
            if HoopVitalDates.days(from: latest.day, to: localToday) == 1 { return same(String(localized: "Yesterday")) }
            let d = HoopVitalDates.short(latest.day)
            return (String(localized: "Latest · \(d)"), String(localized: "Latest reading \(d)"))
        }
        // A skin-temperature deviation already is a comparison with your normal.
        if v.isDeviation(latest.value) { return same(String(localized: "vs your baseline")) }
        if v.cadence == .dailyTotal {
            // Today's total is still climbing, so it isn't set against finished days.
            guard priorWeek.count >= 2 else { return same(String(localized: "Today so far")) }
            let avg = v.formatted(display: priorWeek.reduce(0, +) / Double(priorWeek.count), u)
            return (String(localized: "Today so far · avg \(avg.value)"),
                    String(localized: "Today so far. Average this week \(avg.spoken)"))
        }
        guard priorWeek.count >= 2 else {
            return same(v.cadence == .overnight ? String(localized: "Last night") : String(localized: "Today"))
        }
        let base = priorWeek.reduce(0, +) / Double(priorWeek.count)
        return trend(v, current: v.display(latest.value, u), base: base, u)
    }

    /// "↑ 6% vs your week", "↓ 3 bpm vs your week" or "In line with your week": the latest reading against
    /// the mean of the other days this week.
    private static func trend(_ v: HoopVital, current: Double, base: Double,
                              _ u: HoopVitalUnits) -> (text: String, spoken: String) {
        let steady = String(localized: "In line with your week")
        switch v.delta {
        case .relative:
            guard abs(base) > 0.000_1 else { return (steady, steady) }
            let pct = (current - base) / abs(base) * 100
            guard abs(pct) >= 2 else { return (steady, steady) }
            let n = Int(abs(pct).rounded())
            return pct > 0
                ? (String(localized: "↑ \(n)% vs your week"), String(localized: "Up \(n) percent on your week"))
                : (String(localized: "↓ \(n)% vs your week"), String(localized: "Down \(n) percent on your week"))
        case .absolute:
            let change = current - base
            guard !v.roundsToZero(change, u) else { return (steady, steady) }
            let size = v.deltaText(abs(change), u)
            return change > 0
                ? (String(localized: "↑ \(size.text) vs your week"), String(localized: "Up \(size.spoken) on your week"))
                : (String(localized: "↓ \(size.text) vs your week"), String(localized: "Down \(size.spoken) on your week"))
        }
    }

    /// When the latest occasional reading was taken, and how it moved from the one before.
    private static func occasional(_ v: HoopVital, latest: HoopVitalPoint, points: [HoopVitalPoint],
                                   u: HoopVitalUnits, localToday: String) -> (text: String, spoken: String) {
        // A reading more than a week old leads with its date, not with a change.
        guard HoopVitalDates.days(from: latest.day, to: localToday) <= 7 else {
            let d = HoopVitalDates.short(latest.day)
            return (String(localized: "As of \(d)"), String(localized: "Last reading \(d)"))
        }
        let when = HoopVitalDates.relative(latest.day, today: localToday)
        guard let previous = points.dropLast().last else { return when }
        if v.manual == .bloodPressure {
            let was = v.text(previous.value, diastolic: previous.value2, u)
            return (String(localized: "\(when.text) · was \(was.value)"),
                    String(localized: "\(when.spoken). The reading before was \(was.spoken)"))
        }
        let change = v.display(latest.value, u) - v.display(previous.value, u)
        guard !v.roundsToZero(change, u) else {
            return (String(localized: "\(when.text) · unchanged"),
                    String(localized: "\(when.spoken), unchanged from the reading before"))
        }
        let size = v.deltaText(abs(change), u)
        return change > 0
            ? (String(localized: "\(when.text) · ↑ \(size.text)"),
               String(localized: "\(when.spoken), up \(size.spoken) from the reading before"))
            : (String(localized: "\(when.text) · ↓ \(size.text)"),
               String(localized: "\(when.spoken), down \(size.spoken) from the reading before"))
    }
}
#endif
