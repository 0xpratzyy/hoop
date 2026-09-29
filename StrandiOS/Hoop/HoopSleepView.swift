#if os(iOS)
import SwiftUI
import WhoopStore
import StrandAnalytics

/// Sleep: last night's performance hoop and time asleep, bed → wake, the night's stages, and the last
/// seven nights against the need.
struct HoopSleepView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var lastNight: CachedSleepSession?
    @State private var nights: [String: CachedSleepSession] = [:]
    @State private var score: Double?
    @State private var scoreByDay: [String: Double] = [:]
    @State private var showInfo = false
    /// The night whose hours the week chart reads out; nil means the latest.
    @State private var selectedNight: String?

    private var day: DailyMetric? { repo.today }
    private var need: Double { SleepModel.debtNeedMin(days: repo.days) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    if day?.totalSleepMin != nil {
                        timesRow.padding(.top, HoopSpace.xxl + 4)
                        HoopAISleepInsight(nightKey: insightKey)
                            .padding(.top, HoopSpace.section)
                        stagesSection
                    }
                    HoopSectionHeader("Last 7 nights") {
                        HStack(spacing: 6) {
                            DashedRule().frame(width: 14, height: 1.5)
                            Text("Need \(HoopFormat.hoursMinutes(need))")
                                .font(HoopFont.footnote)
                                .foregroundStyle(HoopColor.textTertiary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    weekSurface
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .hoopTabRoot("Sleep")
            .hoopNavigationSubtitle(nightLabel)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HoopAskButton(topic: .sleep) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInfo = true } label: { Image(systemName: "info") }
                        .accessibilityLabel("About sleep")
                }
            }
            .refreshable {
                ble.syncNow()
                await repo.refresh()
                await load()
            }
        }
        .task { await load() }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await load() } }
        .sheet(isPresented: $showInfo) { HoopInfoSheet(topic: .sleep) }
    }

    /// The night an AI insight belongs to: the main block's wake time, else today's row.
    private var insightKey: String {
        if let n = lastNight { return "\(n.effectiveStartTs)-\(n.endTs)" }
        return day?.day ?? Repository.localDayKey(Date())
    }

    private var nightLabel: String {
        guard let n = lastNight else { return String(localized: "Last night") }
        let start = Date(timeIntervalSince1970: TimeInterval(n.effectiveStartTs))
        let end = Date(timeIntervalSince1970: TimeInterval(n.endTs))
        return "\(start.formatted(.dateTime.weekday(.abbreviated))) – \(end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    // MARK: Hero

    private var hero: some View {
        let asleep = day?.totalSleepMin
        let pct = score ?? asleep.map { min($0 / max(need, 1) * 100, 100) }
        return VStack(spacing: HoopSpace.xl) {
            ZStack {
                HoopRing(progress: (pct ?? 0) / 100, tint: HoopColor.sleep, lineWidth: 16)
                Group {
                    if let pct {
                        VStack(spacing: 0) {
                            HoopHeroNumber(value: "\(Int(pct.rounded()))", symbol: "%", size: 70)
                            Text(score != nil ? "Performance" : "Of your need")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(HoopColor.textTertiary)
                            Text("Sleep")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(width: 224, height: 224)
            .background {
                if pct != nil { HoopGlow(tint: HoopColor.sleep).frame(width: 440, height: 440) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pct.map {
                score != nil
                    ? String(localized: "Sleep performance \(Int($0.rounded())) percent")
                    : String(localized: "\(Int($0.rounded())) percent of your sleep need")
            } ?? String(localized: "No sleep score"))

            if let asleep {
                VStack(spacing: 4) {
                    HoopValue(value: HoopFormat.hoursMinutes(asleep), unit: String(localized: "asleep"),
                              font: HoopFont.value(.title), unitFont: HoopFont.subhead)
                    Text("\(HoopFormat.hoursMinutes(need)) needed")
                        .font(HoopFont.subhead)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 6) {
                    Text("No sleep recorded last night")
                        .font(HoopFont.title3)
                        .foregroundStyle(HoopColor.text)
                    Text("Wear your strap to bed. Hoop detects your sleep automatically and scores it when you sync in the morning.")
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HoopSpace.l)
    }

    private var timesRow: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: HoopSpace.l)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            HoopStat(label: "Bedtime", value: lastNight.map { HoopFormat.clock($0.effectiveStartTs) } ?? HoopFormat.dash)
            if !stacked { statDivider }
            HoopStat(label: "Woke", value: lastNight.map { HoopFormat.clock($0.endTs) } ?? HoopFormat.dash)
            if !stacked { statDivider }
            HoopStat(label: "Efficiency", value: efficiencyText)
        }
    }

    private var statDivider: some View {
        Rectangle().fill(HoopColor.hairline).frame(width: 1, height: 30)
    }

    private var efficiencyText: String {
        guard let e = day?.efficiency ?? lastNight?.efficiency else { return HoopFormat.dash }
        return "\(Int((e <= 1 ? e * 100 : e).rounded()))%"
    }

    // MARK: Stages

    private struct StagePart: Identifiable {
        let id: String
        let name: LocalizedStringKey
        let minutes: Double
        let color: Color
    }

    private var stageParts: [StagePart] {
        let inBed = lastNight.map { Double($0.endTs - $0.effectiveStartTs) / 60 }
        let asleep = day?.totalSleepMin ?? 0
        let awake = max((inBed ?? 0) - asleep, 0)
        return [
            StagePart(id: "deep", name: "Deep", minutes: day?.deepMin ?? 0, color: HoopColor.stageDeep),
            StagePart(id: "rem", name: "REM", minutes: day?.remMin ?? 0, color: HoopColor.stageREM),
            StagePart(id: "light", name: "Light", minutes: day?.lightMin ?? 0, color: HoopColor.stageLight),
            StagePart(id: "awake", name: "Awake", minutes: awake, color: HoopColor.stageAwake),
        ]
    }

    @ViewBuilder
    private var stagesSection: some View {
        let parts = stageParts
        let total = max(parts.reduce(0) { $0 + $1.minutes }, 1)
        let hasStages = parts.prefix(3).contains { $0.minutes > 0 }
        let segments = lastNight.map { AnalyticsEngine.decodeStages($0.stagesJSON) } ?? []

        HoopSectionHeader("Stages")
        HoopSurface(padding: HoopSpace.l + 2) {
            VStack(alignment: .leading, spacing: HoopSpace.l) {
                if let night = lastNight, !segments.isEmpty {
                    VStack(spacing: HoopSpace.s) {
                        HoopHypnogram(segments: segments, start: night.effectiveStartTs, end: night.endTs)
                            .frame(height: 132)
                        HStack {
                            Text(HoopFormat.clock(night.effectiveStartTs))
                            Spacer()
                            Text(HoopFormat.clock(night.endTs))
                        }
                        .font(HoopFont.caption2)
                        .foregroundStyle(HoopColor.textTertiary)
                        .padding(.leading, HoopHypnogram.labelWidth)
                    }
                    if hasStages { HoopDivider() }
                }
                if hasStages {
                    LazyVGrid(columns: typeSize.isAccessibilitySize
                              ? [GridItem(.flexible())]
                              : [GridItem(.flexible(), spacing: HoopSpace.l), GridItem(.flexible())],
                              alignment: .leading, spacing: HoopSpace.l) {
                        ForEach(parts) { p in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(p.color).frame(width: 8, height: 8).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(HoopFont.footnote)
                                        .foregroundStyle(HoopColor.textSecondary)
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(HoopFormat.hoursMinutes(p.minutes))
                                            .font(HoopFont.value(.headline))
                                            .foregroundStyle(HoopColor.text)
                                        Text("\(Int((p.minutes / total * 100).rounded()))%")
                                            .font(HoopFont.value(.footnote, .medium))
                                            .foregroundStyle(HoopColor.textTertiary)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else if segments.isEmpty {
                    Text("Stages appear once a night has been scored.")
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textTertiary)
                }
            }
        }
    }

    // MARK: Week

    private struct Night: Identifiable {
        let id: String
        let date: Date
        let asleepMin: Double?
        let isToday: Bool
    }

    private var week: [Night] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<7).reversed().compactMap { back in
            guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let k = Repository.localDayKey(date)
            let asleep = back == 0 ? (repo.today?.totalSleepMin ?? byDay[k]?.totalSleepMin) : byDay[k]?.totalSleepMin
            return Night(id: k, date: date, asleepMin: asleep, isToday: back == 0)
        }
    }

    private var weekSurface: some View {
        let w = week
        let peak = max(w.compactMap(\.asleepMin).max() ?? need, need) * 1.1
        let barH: CGFloat = 116
        let asleep = w.compactMap(\.asleepMin)
        let blocks = Array(nights.values)
        let stacked = typeSize.isAccessibilitySize
        let statsLayout = stacked ? AnyLayout(VStackLayout(spacing: HoopSpace.l)) : AnyLayout(HStackLayout(spacing: 0))
        let selected = selectedNight ?? w.last(where: { $0.asleepMin != nil })?.id
        return HoopSurface(padding: HoopSpace.l + 2) {
            VStack(spacing: HoopSpace.l) {
                VStack(spacing: HoopSpace.s) {
                    // One reading at a time: the selected night's hours sit above its bar.
                    HStack(spacing: 0) {
                        ForEach(w) { n in
                            Text(n.id == selected ? (n.asleepMin.map { HoopFormat.hoursMinutes($0) } ?? HoopFormat.dash) : " ")
                                .font(HoopFont.value(.caption, .semibold))
                                .foregroundStyle(HoopColor.text)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: selected)
                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(w) { n in
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(HoopColor.track.opacity(0.6))
                                    if let m = n.asleepMin {
                                        Capsule()
                                            .fill(HoopColor.sleep.opacity(m >= need ? 1 : 0.42))
                                            .frame(height: max(14, barH * m / peak))
                                    }
                                }
                                .frame(width: 14, height: barH)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedNight = n.id }
                            }
                        }
                        DashedRule()
                            .frame(height: 1.5)
                            .offset(y: -barH * need / peak)
                            .allowsHitTesting(false)
                    }
                    .frame(height: barH)
                    HStack(spacing: 0) {
                        ForEach(w) { n in
                            Text(n.date.formatted(.dateTime.weekday(.narrow)))
                                .font(HoopFont.caption2.weight(n.id == selected ? .semibold : .regular))
                                .foregroundStyle(n.id == selected ? HoopColor.text : HoopColor.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(weekAccessibility(w))
                HoopDivider()
                statsLayout {
                    HoopStat(label: "Avg sleep",
                             value: asleep.isEmpty ? HoopFormat.dash
                                : HoopFormat.hoursMinutes(asleep.reduce(0, +) / Double(asleep.count)))
                    if !stacked { statDivider }
                    HoopStat(label: "Avg bedtime", value: averageClock(blocks.map(\.effectiveStartTs)))
                    if !stacked { statDivider }
                    HoopStat(label: "Avg wake", value: averageClock(blocks.map(\.endTs)))
                }
            }
        }
    }

    private func weekAccessibility(_ w: [Night]) -> String {
        let parts = w.map { n -> String in
            let day = n.date.formatted(.dateTime.weekday(.wide))
            return n.asleepMin.map { "\(day) \(HoopFormat.hoursMinutes($0))" } ?? String(localized: "\(day) no sleep recorded")
        }
        return String(localized: "Hours asleep, last seven nights: \(parts.joined(separator: ", "))")
    }

    /// Mean clock time of timestamps, wrapped around noon so 23:30 and 00:30 average to midnight.
    private func averageClock(_ ts: [Int]) -> String {
        guard !ts.isEmpty else { return HoopFormat.dash }
        let cal = Calendar.current
        let mins = ts.map { t -> Int in
            let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(t)))
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            return m < 12 * 60 ? m + 24 * 60 : m
        }
        let mean = (mins.reduce(0, +) / mins.count) % (24 * 60)
        let date = cal.date(bySettingHour: mean / 60, minute: mean % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Load

    private func load() async {
        let blocks = await repo.allSleepSessions(days: 8)
        var byDay: [String: CachedSleepSession] = [:]
        for b in blocks {
            let k = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(b.endTs)))
            if let cur = byDay[k], cur.endTs - cur.effectiveStartTs >= b.endTs - b.effectiveStartTs { continue }
            byDay[k] = b
        }
        nights = byDay
        lastNight = LastNightCard.pick(blocks)
        let series = await repo.exploreSeries(key: "sleep_performance", source: Repository.whoopSource)
        let map = Dictionary(series.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        scoreByDay = map
        let todayKey = repo.today?.day ?? Repository.logicalDayKey(Date())
        score = TodayView.freshRestScore(todayValue: map[todayKey], lastDay: series.last?.day,
                                         lastValue: series.last?.value, isTodaySelected: true, todayKey: todayKey)
    }
}

/// A short dashed rule (the "need" line and its legend).
struct DashedRule: View {
    var color: Color = HoopColor.textTertiary

    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: g.size.height, lineCap: .round, dash: [3, 4]))
        }
        .accessibilityHidden(true)
    }
}

/// Four-lane hypnogram: Awake on top, then REM, Light and Deep. One rounded block per segment, joined by
/// hairline risers where the night moves between stages.
struct HoopHypnogram: View {
    let segments: [StageSegment]
    let start: Int
    let end: Int

    static let labelWidth: CGFloat = 46

    private func lane(_ stage: String) -> Int {
        switch stage.lowercased() {
        case "wake", "awake": return 0
        case "rem": return 1
        case "light": return 2
        default: return 3
        }
    }

    private static let colors = [HoopColor.stageAwake, HoopColor.stageREM, HoopColor.stageLight, HoopColor.stageDeep]

    var body: some View {
        let names: [LocalizedStringKey] = ["Awake", "REM", "Light", "Deep"]
        Canvas { ctx, size in
            let labelW = Self.labelWidth
            let w = max(size.width - labelW, 1)
            let laneH = size.height / 4
            let span = max(Double(end - start), 1)

            for i in 0..<4 {
                let y = CGFloat(i) * laneH + laneH / 2
                var guide = Path()
                guide.move(to: CGPoint(x: labelW, y: y))
                guide.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(guide, with: .color(HoopColor.hairline), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                ctx.draw(Text(names[i]).font(HoopFont.caption2).foregroundStyle(HoopColor.textTertiary),
                         at: CGPoint(x: 0, y: y), anchor: .leading)
            }

            let blockH = laneH * 0.56
            let sorted = segments.sorted { $0.start < $1.start }
            var previous: (x: CGFloat, lane: Int)?
            for seg in sorted {
                let s = max(seg.start, start), e = min(seg.end, end)
                guard e > s else { continue }
                let l = lane(seg.stage)
                let x0 = labelW + w * CGFloat(Double(s - start) / span)
                let x1 = labelW + w * CGFloat(Double(e - start) / span)
                if let prev = previous, prev.lane != l, abs(prev.x - x0) < 3 {
                    let yA = CGFloat(prev.lane) * laneH + laneH / 2
                    let yB = CGFloat(l) * laneH + laneH / 2
                    var riser = Path()
                    riser.move(to: CGPoint(x: x0, y: min(yA, yB) + blockH / 2))
                    riser.addLine(to: CGPoint(x: x0, y: max(yA, yB) - blockH / 2))
                    ctx.stroke(riser, with: .color(Color.white.opacity(0.16)), lineWidth: 1)
                }
                let rect = CGRect(x: x0, y: CGFloat(l) * laneH + (laneH - blockH) / 2,
                                  width: max(2, x1 - x0), height: blockH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2), style: .continuous),
                         with: .color(Self.colors[l]))
                previous = (x1, l)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Sleep stages chart")
    }
}
#endif
