#if os(iOS)
import StrandDesign
import SwiftUI
import WhoopStore
import StrandAnalytics

/// Hoop's home. One hoop, recovery, carries the screen; strain and sleep sit quietly beneath it, then
/// the heart, the vitals the person chose (`HoopVitalsSection`) and today's activity, set as type rather
/// than tiles.
struct HoopTodayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dynamicTypeSize) private var typeSize

    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    private var effortScale: EffortScale { EffortScale(rawValue: effortScaleRaw) ?? .whoop }

    @State private var snap = HoopTodaySnapshot()
    @State private var showLive = false
    @State private var showStrap = false
    @State private var infoTopic: HoopInfoTopic?

    /// Switches to another tab (Sleep) from a card tap.
    var openTab: (HoopTab) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    HoopAIBriefing(snapshot: snap)
                        .padding(.top, HoopSpace.section)
                    scores
                        .padding(.top, HoopSpace.section + 4)
                    HoopLiveHeartCard(curve: snap.hrCurve, range: snap.hrCurveRange) { showLive = true }
                        .padding(.top, HoopSpace.m)
                    // The vitals the person chose, in their order (StrandiOS/Hoop/Vitals).
                    HoopVitalsSection(snapshot: snap)
                    HoopSectionHeader("Activity")
                    activity
                    footnote
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .hoopTabRoot("Today")
            .hoopNavigationSubtitle(HoopFormat.longDate())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HoopAskButton(topic: .today) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showStrap = true } label: { HoopStrapStatus() }
                }
            }
            .refreshable {
                ble.syncNow()
                await repo.refresh()
                await reload()
            }
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await reload() } }
        .sheet(isPresented: $showLive) { HoopLiveHeartView() }
        .sheet(isPresented: $showStrap) { HoopStrapSheet() }
        .sheet(item: $infoTopic) { HoopInfoSheet(topic: $0) }
    }

    private func reload() async {
        var s = await HoopTodayLoader.load(repo: repo, profile: profile)
        #if DEBUG
        if let forced = Self.debugCharge { s.charge = forced }
        #endif
        withAnimation(.easeOut(duration: 0.35)) { snap = s }
    }

    #if DEBUG
    /// DEBUG screenshot aid: `--hoop-charge scored:78|carried:64|calibrating:2|none` pins the hero to one
    /// state so the honest empty and carried states can be checked against seeded data. The loader's
    /// resolution is untouched; this only replaces its answer for display.
    private static var debugCharge: LiquidTodayView.ChargeDisplay? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--hoop-charge"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ":").map(String.init)
        let n = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
        switch parts.first {
        case "scored": return .scored(pct: n)
        case "carried":
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return .carried(pct: n, caption: TodayView.carriedCaption(priorDayKey: Repository.localDayKey(yesterday),
                                                                      todayKey: Repository.logicalDayKey(Date())))
        case "calibrating": return .calibrating(nights: Int(n))
        case "none": return .noData
        default: return nil
        }
    }
    #endif

    // MARK: Recovery hero

    private var hero: some View {
        let charge = snap.charge
        let tint = HoopColor.recovery(charge.pct)
        return Button { infoTopic = .recovery } label: {
            VStack(spacing: HoopSpace.xl) {
                ZStack {
                    HoopRing(progress: ringProgress, tint: ringTint, lineWidth: 16)
                    heroCenter
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .frame(width: 240, height: 240)
                .background {
                    if charge.pct != nil {
                        HoopGlow(tint: tint).frame(width: 460, height: 460)
                    }
                }
                VStack(spacing: 6) {
                    Text(HoopRecoveryCopy.title(charge))
                        .font(HoopFont.title3)
                        .foregroundStyle(HoopColor.text)
                    Text(HoopRecoveryCopy.guidance(charge))
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .carried(_, let caption) = charge {
                        Label(caption, systemImage: "clock.arrow.circlepath")
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textTertiary)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 330)
                if snap.recoveryWeek.contains(where: { $0 != nil }) {
                    HoopWeekStrip(values: snap.recoveryWeek, color: { HoopColor.recovery($0) })
                        .padding(.top, HoopSpace.s)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, HoopSpace.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoopPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibilityLabel)
        .accessibilityHint("Explains recovery")
        .accessibilityAddTraits(.isButton)
    }

    private var ringProgress: Double {
        switch snap.charge {
        case .scored(let p), .carried(let p, _): return p / 100
        case .calibrating(let n): return Double(min(n, Baselines.minNightsSeed)) / Double(Baselines.minNightsSeed)
        case .noData: return 0
        }
    }

    private var ringTint: Color {
        if case .calibrating = snap.charge { return HoopColor.textSecondary }
        return HoopColor.recovery(snap.charge.pct)
    }

    @ViewBuilder
    private var heroCenter: some View {
        switch snap.charge {
        case .scored(let p), .carried(let p, _):
            VStack(spacing: 0) {
                HoopHeroNumber(value: "\(Int(p.rounded()))", symbol: "%", size: 78)
                Text("Recovery")
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
            }
            .padding(.horizontal, 24)
        case .calibrating(let n):
            let seed = Baselines.minNightsSeed
            VStack(spacing: 2) {
                HoopHeroNumber(value: "\(min(n, seed))", symbol: "/\(seed)", size: 68)
                Text("nights")
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
            }
            .padding(.horizontal, 24)
        case .noData:
            VStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(HoopColor.textTertiary)
                Text("Recovery")
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
            }
        }
    }

    private var heroAccessibilityLabel: String {
        let title = HoopRecoveryCopy.title(snap.charge)
        let guidance = HoopRecoveryCopy.guidance(snap.charge)
        switch snap.charge {
        case .scored(let p):
            return String(localized: "Recovery \(Int(p.rounded())) percent. \(title). \(guidance)")
        case .carried(let p, let caption):
            return String(localized: "Recovery \(Int(p.rounded())) percent, \(caption). \(title). \(guidance)")
        case .calibrating, .noData:
            return "\(title). \(guidance)"
        }
    }

    // MARK: Strain + Sleep

    private var scores: some View {
        let strainValue = snap.strain.map { UnitFormatter.effortValue($0, scale: effortScale) }
        let strainMax: Double = effortScale == .whoop ? 21 : 100
        let accessibilityStack = typeSize.isAccessibilitySize
        let layout = accessibilityStack ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            Button { infoTopic = .strain } label: {
                HoopScoreCell(title: "Strain",
                              progress: (strainValue ?? 0) / strainMax,
                              tint: HoopColor.strain,
                              value: strainValue.map { String(format: "%.1f", $0) } ?? HoopFormat.dash,
                              unit: strainValue == nil ? "" : String(localized: "of \(Int(strainMax))"),
                              caption: strainCaption(strainValue, max: strainMax))
            }
            .buttonStyle(HoopPressStyle())
            .accessibilityHint("Explains strain")

            if accessibilityStack {
                HoopDivider().padding(.horizontal, HoopSpace.l)
            } else {
                Rectangle().fill(HoopColor.hairline).frame(width: 1).padding(.vertical, HoopSpace.xl)
            }

            Button { openTab(.sleep) } label: {
                HoopScoreCell(title: "Sleep",
                              progress: (snap.sleepScore ?? 0) / 100,
                              tint: HoopColor.sleep,
                              value: snap.sleepScore.map { "\(Int($0.rounded()))" } ?? HoopFormat.dash,
                              unit: snap.sleepScore == nil ? "" : "%",
                              caption: sleepCaption)
            }
            .buttonStyle(HoopPressStyle())
            .accessibilityHint("Opens Sleep")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous).fill(HoopColor.surface))
    }

    private func strainCaption(_ v: Double?, max: Double) -> String {
        guard let v else { return String(localized: "Builds as you move today") }
        let f = v / max
        if f < 0.33 { return String(localized: "Light day so far") }
        if f < 0.66 { return String(localized: "Moderate effort") }
        if f < 0.85 { return String(localized: "Strenuous day") }
        return String(localized: "All out")
    }

    private var sleepCaption: String {
        guard let m = snap.sleepMinutes else { return String(localized: "No night recorded yet") }
        if let need = snap.sleepNeedMinutes, need > 0 {
            return String(localized: "\(HoopFormat.hoursMinutes(m)) of \(HoopFormat.hoursMinutes(need)) needed")
        }
        return String(localized: "\(HoopFormat.hoursMinutes(m)) asleep")
    }

    // MARK: Activity

    private var activity: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout {
            activityCell("Calories", value: HoopFormat.int(snap.totalKcal), unit: "kcal",
                         caption: snap.activeKcal.map { "\(HoopFormat.int($0)) " + String(localized: "active") }
                            ?? String(localized: "Burned today"),
                         progress: nil)
            if stacked {
                HoopDivider().padding(.horizontal, HoopSpace.l)
            } else {
                Rectangle().fill(HoopColor.hairline).frame(width: 1).padding(.vertical, HoopSpace.xl)
            }
            activityCell("Steps", value: HoopFormat.int(snap.steps), unit: "", caption: stepsCaption,
                         progress: snap.steps.map { $0 / 10_000 })
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous).fill(HoopColor.surface))
    }

    private func activityCell(_ title: LocalizedStringKey, value: String, unit: String, caption: String,
                              progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
            HoopValue(value: value, unit: unit, font: HoopFont.value(.title2))
            Text(caption)
                .font(HoopFont.caption)
                .foregroundStyle(HoopColor.textTertiary)
                .lineLimit(2)
            if let progress {
                HoopBar(progress: progress, tint: HoopColor.text.opacity(0.85), height: 4)
                    .padding(.top, 6)
            }
        }
        .padding(HoopSpace.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stepsCaption: String {
        guard let s = snap.steps else { return String(localized: "Goal 10,000") }
        let left = 10_000 - s
        return left > 0 ? String(localized: "\(HoopFormat.int(left)) to 10,000") : String(localized: "Goal reached")
    }

    private var footnote: some View {
        Text("Estimates from your strap, computed on this iPhone. Not medical advice.")
            .font(HoopFont.caption)
            .foregroundStyle(HoopColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, HoopSpace.xxl)
            .padding(.horizontal, HoopSpace.l)
    }
}

// MARK: - Pieces

/// Half of the strain | sleep surface: a small hoop, the number, and a one-line read of it.
struct HoopScoreCell: View {
    let title: LocalizedStringKey
    let progress: Double
    let tint: Color
    let value: String
    var unit: String = ""
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(title)
                    .font(HoopFont.subhead.weight(.medium))
                    .foregroundStyle(HoopColor.textSecondary)
                Spacer(minLength: HoopSpace.s)
                HoopRing(progress: progress, tint: tint, lineWidth: 4.5)
                    .frame(width: 30, height: 30)
            }
            HoopValue(value: value, unit: unit, font: HoopFont.value(.title), unitFont: HoopFont.footnote)
                .padding(.top, 2)
            Text(caption)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HoopSpace.l + 2)
        .padding(.vertical, HoopSpace.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The live heart-rate row. Its own view so a per-second heart-rate tick re-renders only this card,
/// not the whole Today screen.
struct HoopLiveHeartCard: View {
    let curve: [Double]
    let range: ClosedRange<Double>?
    let onTap: () -> Void

    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var model: AppModel

    private var liveBpm: Int? {
        guard live.connected else { return nil }
        if let b = model.bpm, b > 0 { return b }
        if let h = live.heartRate, h > 0 { return h }
        return nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HoopSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        HoopHeartGlyph(bpm: liveBpm, size: 12)
                        Text("Heart rate")
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                        if liveBpm != nil { HoopLiveDot(tint: HoopColor.heart) }
                    }
                    if let liveBpm {
                        HoopValue(value: "\(liveBpm)", unit: "bpm", font: HoopFont.value(.title), unitFont: HoopFont.footnote)
                    } else {
                        Text(live.connected ? "Tap to go live" : "Not connected")
                            .font(HoopFont.title3)
                            .foregroundStyle(live.connected ? HoopColor.text : HoopColor.textSecondary)
                            .padding(.vertical, 2)
                    }
                    if let caption {
                        Text(caption)
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: HoopSpace.s)
                if curve.count >= 2 {
                    HoopSparkline(values: Array(curve.suffix(72)).map { Optional($0) },
                                  tint: liveBpm != nil ? HoopColor.heart : HoopColor.textTertiary,
                                  lineWidth: 1.5)
                        .frame(width: 92, height: 34)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textTertiary)
            }
            .padding(.horizontal, HoopSpace.l + 2)
            .padding(.vertical, HoopSpace.l)
            .background(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous).fill(HoopColor.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(HoopPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens live heart rate")
    }

    /// Today's range when there is one (it is history, so it stays true offline), else a live hint.
    private var caption: String? {
        if let range {
            return String(localized: "Today \(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) bpm")
        }
        if liveBpm != nil { return String(localized: "Live from your strap") }
        if !live.connected { return String(localized: "Connect your strap to go live") }
        return nil
    }
}

/// Seven slim bars for the week, filled to each day's score and coloured by it; today last and brightest.
struct HoopWeekStrip: View {
    let values: [Double?]
    let color: (Double) -> Color
    var height: CGFloat = 30

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let isToday = i == values.count - 1
                let date = cal.date(byAdding: .day, value: i - (values.count - 1), to: today) ?? today
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(HoopColor.track).frame(width: 6, height: height)
                        if let v {
                            Capsule()
                                .fill(color(v).opacity(isToday ? 1 : 0.75))
                                .frame(width: 6, height: max(6, height * CGFloat(min(max(v, 0), 100)) / 100))
                        }
                    }
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(HoopFont.caption2.weight(isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? HoopColor.text : HoopColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let parts: [String] = values.enumerated().map { i, v in
            let date = cal.date(byAdding: .day, value: i - (values.count - 1), to: today) ?? today
            let day = date.formatted(.dateTime.weekday(.wide))
            return v.map { "\(day) \(Int($0.rounded()))" } ?? String(localized: "\(day) no score")
        }
        return String(localized: "Last seven days: \(parts.joined(separator: ", "))")
    }
}

/// A heart that beats at the live rate, or rests still with no reading (and under Reduce Motion).
struct HoopHeartGlyph: View {
    let bpm: Int?
    var size: CGFloat = 14
    var color: Color = HoopColor.heart
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var beat = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(bpm == nil ? HoopColor.textTertiary : color)
            .scaleEffect(beat ? 1.16 : 1)
            .task(id: bpm) {
                guard let bpm, bpm > 20, !motion.poseStill(reduceMotion) else { beat = false; return }
                let period = 60.0 / Double(bpm)
                while !Task.isCancelled {
                    withAnimation(.easeOut(duration: period * 0.22)) { beat = true }
                    try? await Task.sleep(nanoseconds: UInt64(period * 0.26 * 1_000_000_000))
                    withAnimation(.easeIn(duration: period * 0.55)) { beat = false }
                    try? await Task.sleep(nanoseconds: UInt64(period * 0.74 * 1_000_000_000))
                }
            }
            .accessibilityHidden(true)
    }
}

/// The strap's battery as a tiny hoop: charge arc coloured by level, grey when offline, a bolt while
/// charging.
struct HoopBatteryGlyph: View {
    let pct: Double?
    var charging = false
    var connected = true
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().inset(by: lineWidth / 2).stroke(HoopColor.track, lineWidth: lineWidth)
            if let pct, pct > 0 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: min(pct, 100) / 100)
                    .stroke(connected ? HoopColor.battery(pct, charging: charging) : HoopColor.textTertiary,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if charging && connected {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(HoopColor.recoveryHigh)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The strap control in the Today toolbar: a battery hoop and one word of state.
struct HoopStrapStatus: View {
    @EnvironmentObject private var live: LiveState

    /// The strap's own last reported charge. Never cleared on disconnect, so it is only shown as a
    /// number while connected, and only when the active device is the strap (see `LiveState.batteryPct`).
    private var pct: Double? { live.activeIsWhoop ? live.batteryPct : nil }

    var body: some View {
        HStack(spacing: 7) {
            if live.connected {
                HoopBatteryGlyph(pct: pct, charging: live.charging == true, connected: true)
                    .frame(width: 18, height: 18)
            } else {
                Circle().fill(HoopColor.textTertiary).frame(width: 7, height: 7)
            }
            Text(statusText)
                .font(HoopFont.subhead.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(live.connected ? HoopColor.text : HoopColor.textSecondary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusText: String {
        if live.backfilling { return String(localized: "Syncing") }
        guard live.connected else { return String(localized: "Offline") }
        if let pct { return "\(Int(pct.rounded()))%" }
        return String(localized: "Connected")
    }

    private var accessibilityText: String {
        if live.backfilling { return String(localized: "Strap syncing") }
        guard live.connected else { return String(localized: "Strap not connected") }
        if let pct { return String(localized: "Strap connected, battery \(Int(pct.rounded())) percent") }
        return String(localized: "Strap connected")
    }
}
#endif
