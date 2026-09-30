#if os(iOS)
import SwiftUI
import WhoopStore
import WhoopProtocol
import StrandAnalytics

/// Everything the Hoop Today screen shows, resolved once per load so the view body never scans the day
/// history. Scores go through the same resolvers the NOOP screens use (recovery carry-over, calibration,
/// live strain, fresh-only sleep score), so Hoop never shows a number the engine would not.
struct HoopTodaySnapshot: Equatable {
    var charge: LiquidTodayView.ChargeDisplay = .noData
    /// Stored 0–100 strain scale; convert for display with `UnitFormatter.effortValue`.
    var strain: Double?
    /// 0–100 sleep performance.
    var sleepScore: Double?
    var sleepMinutes: Double?
    var sleepNeedMinutes: Double?
    var hrv: Double?
    var restingHr: Double?
    var respRate: Double?
    var spo2: Double?
    var skinTempDev: Double?
    var totalKcal: Double?
    var activeKcal: Double?
    var steps: Double?
    /// Last seven calendar days, oldest first; nil where a day has no value.
    var recoveryWeek: [Double?] = []
    var strainWeek: [Double?] = []
    var sleepWeek: [Double?] = []
    var hrvWeek: [Double?] = []
    var rhrWeek: [Double?] = []
    /// Five-minute heart-rate means since midnight, for the day curve.
    var hrCurve: [Double] = []
    var hrCurveRange: ClosedRange<Double>? = nil
    var loaded = false

    // Provenance, for the Vitals section: the key of the day row each value above was read from (today's
    // own row, or the prior night it was carried from), set beside the value from the SAME row, so a
    // "Last night · 28 Sep" caption can never name a different night than the number next to it.
    /// The day key the loader resolved as today (today's row, else the logical day).
    var todayKey: String = ""
    var hrvDay: String?
    var restingHrDay: String?
    var respRateDay: String?
    var spo2Day: String?
    var skinTempDay: String?
    /// The day the shown recovery was scored for: today when scored, the carried day when carried.
    var chargeDay: String?
    /// The day of the sleep score shown (today's, or last night's carried inside the freshness window).
    var sleepScoreDay: String?

    /// True once the wearer has any strap history at all; drives the first-run empty state.
    var hasAnyData: Bool {
        charge.pct != nil || strain != nil || sleepMinutes != nil || hrv != nil || !hrCurve.isEmpty
    }
}

@MainActor
enum HoopTodayLoader {
    static func load(repo: Repository, profile: ProfileStore) async -> HoopTodaySnapshot {
        var s = HoopTodaySnapshot()
        let now = Date()
        let cal = Calendar.current
        let days = repo.days
        let day = repo.today
        let todayKey = day?.day ?? Repository.logicalDayKey(now)

        // Recovery, with the honest carry / calibration states.
        let calNights = RecoveryScorer.calibrationNights(nightlyHrv: days.map(\.avgHrv),
                                                         dayKeys: days.map(\.day),
                                                         hasRecovery: day?.recovery != nil)
        let prior = TodayView.lastScoredRecoveryDay(days: days, selectedDayKey: todayKey, isToday: true,
                                                    todayScored: day?.recovery != nil,
                                                    isCalibrating: calNights != nil)
        s.charge = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: day?.recovery, priorScored: prior,
                                                         calibrationNights: calNights, todayKey: todayKey)

        // Vitals: today's own reading first, else the freshest prior night that has one.
        let hrvDay = Repository.lastHrvDay(days: days, todayKey: todayKey)
        let rhrDay = Repository.lastRestingHrDay(days: days, todayKey: todayKey)
        let respDay = Repository.lastRespDay(days: days, todayKey: todayKey)
        let vitalsDay = Repository.lastVitalsDay(days: days, todayKey: todayKey)
        s.hrv = day?.avgHrv ?? hrvDay?.avgHrv
        s.restingHr = (day?.restingHr ?? rhrDay?.restingHr).map(Double.init)
        s.respRate = day?.respRateBpm ?? respDay?.respRateBpm
        s.spo2 = day?.spo2Pct ?? vitalsDay?.spo2Pct
        s.skinTempDev = day?.skinTempDevC ?? vitalsDay?.skinTempDevC
        // Which row each vital above came from, mirroring each `??` exactly (additive; the values are
        // resolved above and unchanged).
        s.todayKey = todayKey
        s.hrvDay = day?.avgHrv != nil ? day?.day : hrvDay?.day
        s.restingHrDay = day?.restingHr != nil ? day?.day : rhrDay?.day
        s.respRateDay = day?.respRateBpm != nil ? day?.day : respDay?.day
        s.spo2Day = day?.spo2Pct != nil ? day?.day : (vitalsDay?.spo2Pct != nil ? vitalsDay?.day : nil)
        s.skinTempDay = day?.skinTempDevC != nil ? day?.day : (vitalsDay?.skinTempDevC != nil ? vitalsDay?.day : nil)
        switch s.charge {
        case .scored: s.chargeDay = todayKey
        case .carried: s.chargeDay = prior?.day
        case .calibrating, .noData: s.chargeDay = nil
        }

        // Sleep: minutes from today's row, score from the fresh-only series.
        s.sleepMinutes = day?.totalSleepMin
        s.sleepNeedMinutes = SleepModel.debtNeedMin(days: days)
        let restSeries = await repo.exploreSeries(key: "sleep_performance", source: Repository.whoopSource)
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        s.sleepScore = TodayView.freshRestScore(todayValue: restByDay[todayKey], lastDay: restSeries.last?.day,
                                                lastValue: restSeries.last?.value, isTodaySelected: true,
                                                todayKey: todayKey)
        s.sleepScoreDay = restByDay[todayKey] != nil ? todayKey : (s.sleepScore != nil ? restSeries.last?.day : nil)

        // Today's heart rate: live strain, calories and the day curve all read the same window.
        let dayStart = cal.startOfDay(for: now)
        let from = Int(dayStart.timeIntervalSince1970)
        let to = Int(now.timeIntervalSince1970)
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        let maxHR = profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil
        let restHR = day?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let liveStrain = StrainScorer.strain(hr, maxHR: maxHR, restingHR: restHR,
                                             method: PuffinExperiment.effortMethod, sex: profile.sex)
        s.strain = StrainScorer.effectiveEffort(live: liveStrain, stored: day?.day == todayKey ? day?.strain : nil)

        if !hr.isEmpty {
            let up = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                 age: Double(profile.age), sex: profile.sex)
            let energy = Calories.estimateDayEnergy(hr, profile: up, hrmax: Double(profile.hrMax),
                                                    restingHR: day?.restingHr.map(Double.init))
            s.totalKcal = energy.totalKcal
            s.activeKcal = energy.activeKcal
            s.hrCurve = bucket(hr, from: from, to: to, seconds: 300)
            if let lo = s.hrCurve.min(), let hi = s.hrCurve.max() { s.hrCurveRange = lo...hi }
        }

        // Steps: the strap's measured total, else Apple Health, else the motion estimate.
        let localKey = Repository.localDayKey(now)
        let measured = day?.day == localKey ? day?.steps.map(Double.init) : nil
        let apple = await repo.appleDailyRows(days: 3).filter { $0.day == localKey }.compactMap { $0.steps }.max()
        let est = await repo.exploreSeries(key: "steps_est", source: Repository.whoopSource, days: 3)
            .last { $0.day == localKey }?.value
        s.steps = measured ?? apple.map(Double.init) ?? est

        // Week trends, oldest → newest, keyed by calendar day.
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        let keys: [String] = (0..<7).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: dayStart).map(Repository.localDayKey)
        }
        s.recoveryWeek = keys.map { byDay[$0]?.recovery }
        s.strainWeek = keys.map { k in k == localKey ? s.strain : byDay[k]?.strain }
        s.sleepWeek = keys.map { restByDay[$0] }
        s.hrvWeek = keys.map { byDay[$0]?.avgHrv }
        s.rhrWeek = keys.map { byDay[$0]?.restingHr.map(Double.init) }
        s.loaded = true
        return s
    }

    /// Mean bpm per `seconds`-wide bucket across [from, to]; empty buckets are skipped.
    static func bucket(_ hr: [HRSample], from: Int, to: Int, seconds: Int) -> [Double] {
        guard to > from, seconds > 0 else { return [] }
        var sums: [Int: (Double, Int)] = [:]
        for s in hr where s.ts >= from && s.ts <= to && s.bpm > 25 && s.bpm < 230 {
            let b = (s.ts - from) / seconds
            let cur = sums[b] ?? (0, 0)
            sums[b] = (cur.0 + Double(s.bpm), cur.1 + 1)
        }
        return sums.keys.sorted().compactMap { k in sums[k].map { $0.0 / Double($0.1) } }
    }
}

/// Plain-language read of a recovery score.
enum HoopRecoveryCopy {
    static func title(_ charge: LiquidTodayView.ChargeDisplay) -> String {
        switch charge {
        case .scored(let p), .carried(let p, _):
            if p >= 67 { return String(localized: "Primed") }
            if p >= 34 { return String(localized: "Steady") }
            return String(localized: "Recharge")
        case .calibrating: return String(localized: "Calibrating")
        case .noData: return String(localized: "No score yet")
        }
    }

    static func guidance(_ charge: LiquidTodayView.ChargeDisplay) -> String {
        switch charge {
        case .scored(let p), .carried(let p, _):
            if p >= 67 { return String(localized: "Your body is ready for a big day. Go after it.") }
            if p >= 34 { return String(localized: "A solid base. Train, and listen to how you feel.") }
            return String(localized: "Your body is asking for rest. Keep strain light and sleep early.")
        case .calibrating(let n):
            let seed = Baselines.minNightsSeed
            return String(localized: "Learning your baseline: \(min(n, seed)) of \(seed) nights. Wear your strap to bed.")
        case .noData:
            return String(localized: "Wear your strap overnight and sync in the morning to get your first score.")
        }
    }
}
#endif
