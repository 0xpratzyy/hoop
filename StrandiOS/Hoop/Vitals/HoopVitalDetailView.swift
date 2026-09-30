#if os(iOS)
import Charts
import SwiftUI

/// The chart windows a vital's detail offers.
enum HoopVitalRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "30 days")
        case .quarter: return String(localized: "90 days")
        }
    }
}

extension HoopVitalPoint {
    /// Where a point sits on a time axis: mid-day for a day-keyed series (so it lines up with a day's
    /// bar), the moment itself for a logged reading.
    func plotDate(dayKeyed: Bool) -> Date { dayKeyed ? date.addingTimeInterval(12 * 3_600) : date }
}

/// A vital up close: the latest reading (the same one its Today row shows), a chart over 7, 30 or 90 days,
/// the average and range, what it means, and, for logged vitals, the entries themselves.
struct HoopVitalDetailView: View {
    let vital: HoopVital
    let snapshot: HoopTodaySnapshot

    @EnvironmentObject private var repo: Repository
    @ObservedObject private var log = HoopVitalsLog.shared
    @ObservedObject private var plan = CutPlanStore.shared
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @AppStorage(HoopVitalsPrefs.glucoseUnitKey) private var glucoseRaw = HoopGlucoseUnit.regionalDefault.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var range: HoopVitalRange = .month
    @State private var metricPoints: [HoopVitalPoint]
    @State private var loaded: Bool
    @State private var selection: Date?
    @State private var logRequest: HoopVitalLogRequest?

    /// `preloaded` is the series Today's row already read (the same `HoopVitalsLoader` read), so the
    /// screen opens drawn instead of loading; it still re-reads in the background.
    init(vital: HoopVital, snapshot: HoopTodaySnapshot, preloaded: [HoopVitalPoint]? = nil) {
        self.vital = vital
        self.snapshot = snapshot
        _metricPoints = State(initialValue: preloaded ?? [])
        _loaded = State(initialValue: preloaded != nil)
    }

    private var units: HoopVitalUnits {
        HoopVitalUnits(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw,
                       effortRaw: effortScaleRaw, glucoseRaw: glucoseRaw)
    }

    private var points: [HoopVitalPoint] {
        if let kind = vital.manual { return HoopVitalsLoader.manualPoints(kind, log: log, plan: plan) }
        return metricPoints
    }

    private var ready: Bool { vital.manual != nil || (loaded && snapshot.loaded) }
    private var dayKeyed: Bool { vital.manual == nil }
    private var chartHeight: CGFloat { typeSize.isAccessibilitySize ? 240 : 200 }

    var body: some View {
        let u = units
        let all = points
        let summary = HoopVitalResolver.summary(vital, points: all, snapshot: snapshot, units: u)
        let window = HoopVitalResolver.chartPoints(all, summary: summary, days: range.rawValue, snapshot: snapshot)
        let tint = HoopVitalCopy.tint(vital, latest: summary.latest?.value)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(summary, u)
                Picker("Range", selection: $range) {
                    ForEach(HoopVitalRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, HoopSpace.xxl)
                chartSurface(window, all: all, u: u, tint: tint)
                    .padding(.top, HoopSpace.m)
                if ready && !window.isEmpty {
                    statsSurface(window, u)
                        .padding(.top, HoopSpace.m)
                }
                if let kind = vital.manual {
                    manualSection(kind, all: all, u: u)
                }
                HoopSectionHeader("What it means")
                HoopSurface {
                    Text(HoopVitalCopy.explanation(vital))
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(vital.sourceLabel). Not medical advice.")
                    .font(HoopFont.caption)
                    .foregroundStyle(HoopColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, HoopSpace.m)
            }
            .hoopScreenPadding()
            .padding(.bottom, HoopSpace.xxl)
        }
        .scrollIndicators(.hidden)
        .background(HoopBackground())
        .navigationTitle(vital.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(vital.id)|\(repo.refreshSeq)") { await load() }
        .onChange(of: range) { _, _ in selection = nil }
        .sheet(item: $logRequest) { HoopLogVitalSheet(initial: $0.kind) }
    }

    private func load() async {
        guard let m = vital.metric else { loaded = true; return }
        let loadedPoints = await HoopVitalsLoader.metricPoints(m, repo: repo)
        guard !Task.isCancelled else { return }
        metricPoints = loadedPoints
        loaded = true
    }

    // MARK: Hero

    private func hero(_ s: HoopVitalSummary, _ u: HoopVitalUnits) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HoopValue(value: ready ? s.text.value : HoopFormat.dash, unit: vital.unitLabel(u, compact: false),
                      font: HoopFont.value(.largeTitle), unitFont: HoopFont.headline)
            Group {
                if !ready {
                    Text(verbatim: " ")
                } else if s.carried {
                    Text("\(Image(systemName: "clock.arrow.circlepath")) \(s.caption)")
                } else {
                    Text(s.caption)
                }
            }
            .font(HoopFont.subhead)
            .foregroundStyle(HoopColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, HoopSpace.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HoopVitalRow.accessibilityText(s, ready: ready))
    }

    // MARK: Chart

    private func chartSurface(_ window: [HoopVitalPoint], all: [HoopVitalPoint], u: HoopVitalUnits,
                              tint: Color) -> some View {
        let values = window.map { vital.display($0.value, u) }
        let average = values.isEmpty || vital.manual == .bloodPressure ? nil : values.reduce(0, +) / Double(values.count)
        let selected = selection.flatMap { date in
            window.min { a, b in
                abs(a.plotDate(dayKeyed: dayKeyed).timeIntervalSince(date))
                    < abs(b.plotDate(dayKeyed: dayKeyed).timeIntervalSince(date))
            }
        }
        return HoopSurface(padding: HoopSpace.l) {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                readout(selected: selected, hasPoints: ready && !window.isEmpty, showAverage: average != nil,
                        u: u, tint: tint)
                if !ready {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: chartHeight)
                } else if window.isEmpty {
                    emptyChart(all)
                } else {
                    HoopVitalChart(vital: vital, points: window, units: u, range: range, tint: tint,
                                   average: average, selected: selected, selection: $selection)
                        .frame(height: chartHeight)
                }
            }
        }
    }

    /// Above the chart: the window, or while a finger is on the chart, the reading under it.
    private func readout(selected: HoopVitalPoint?, hasPoints: Bool, showAverage: Bool, u: HoopVitalUnits,
                         tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HoopSpace.s) {
            if let p = selected {
                Text(dateLabel(p))
                    .font(HoopFont.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textSecondary)
                Spacer(minLength: HoopSpace.s)
                let t = vital.text(p.value, diastolic: p.value2, u)
                HoopValue(value: t.value, unit: t.unit, font: HoopFont.value(.headline), unitFont: HoopFont.caption)
            } else {
                Text(String(localized: "Last \(range.rawValue) days"))
                    .font(HoopFont.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textSecondary)
                Spacer(minLength: HoopSpace.s)
                if !hasPoints {
                    EmptyView()
                } else if vital.manual == .bloodPressure {
                    legend(String(localized: "Systolic"), color: tint)
                    legend(String(localized: "Diastolic"), color: tint.opacity(0.5))
                } else if showAverage {
                    HStack(spacing: 6) {
                        DashedRule().frame(width: 14, height: 1.5)
                        Text("Average")
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textTertiary)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .combine)
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(label)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textTertiary)
        }
    }

    private func emptyChart(_ all: [HoopVitalPoint]) -> some View {
        VStack(spacing: 6) {
            Text(vital.manual != nil
                 ? String(localized: "Nothing logged in the last \(range.rawValue) days")
                 : String(localized: "No readings in the last \(range.rawValue) days"))
                .font(HoopFont.subhead)
                .foregroundStyle(HoopColor.textSecondary)
            if let last = all.last {
                Text("The latest is from \(HoopVitalDates.short(last.day)).")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textTertiary)
            } else if let hint = emptyHint {
                Text(hint)
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var emptyHint: String? {
        if vital.manual != nil { return String(localized: "Log a reading to start the chart.") }
        switch vital.metric?.source {
        case "apple-health": return String(localized: "Connect Apple Health in You to bring these in.")
        case "my-whoop":
            return vital.cadence == .overnight
                ? String(localized: "Wear your strap to bed and sync in the morning.")
                : String(localized: "Readings appear as your strap syncs.")
        default: return nil
        }
    }

    private func dateLabel(_ p: HoopVitalPoint) -> String {
        dayKeyed
            ? p.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : p.date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Stats

    private func statsSurface(_ window: [HoopVitalPoint], _ u: HoopVitalUnits) -> some View {
        let stats = HoopVitalStats(vital: vital, points: window, units: u)
        // Blood pressure's pairs are wide; the hero above already names mmHg.
        let showUnit = vital.manual != .bloodPressure
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: HoopSpace.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return HoopSurface(padding: HoopSpace.l + 2) {
            VStack(spacing: HoopSpace.m) {
                layout {
                    HoopStat(label: "Average", value: stats.average.value, unit: showUnit ? stats.average.unit : "")
                    if !stacked { statDivider }
                    HoopStat(label: "Lowest", value: stats.lowest.value, unit: showUnit ? stats.lowest.unit : "")
                    if !stacked { statDivider }
                    HoopStat(label: "Highest", value: stats.highest.value, unit: showUnit ? stats.highest.unit : "")
                }
                Text(countLine(window.count))
                    .font(HoopFont.caption)
                    .foregroundStyle(HoopColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var statDivider: some View {
        Rectangle().fill(HoopColor.hairline).frame(width: 1, height: 34)
    }

    private func countLine(_ n: Int) -> String {
        let days = range.rawValue
        switch vital.cadence {
        case .overnight: return String(localized: "Readings on \(n) of the last \(days) nights")
        case .daily, .dailyTotal: return String(localized: "Readings on \(n) of the last \(days) days")
        case .occasional:
            return n == 1
                ? String(localized: "1 reading in the last \(days) days")
                : String(localized: "\(n) readings in the last \(days) days")
        }
    }

    // MARK: Logged entries

    @ViewBuilder
    private func manualSection(_ kind: HoopManualVital, all: [HoopVitalPoint], u: HoopVitalUnits) -> some View {
        Button(kind.logLabel) { logRequest = HoopVitalLogRequest(kind: kind) }
            .buttonStyle(HoopSecondaryButtonStyle())
            .padding(.top, HoopSpace.l)
        if !all.isEmpty {
            let recent = Array(all.reversed().prefix(30))
            HoopSectionHeader("Your entries")
            HoopGroup {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, p in
                    entryRow(p, kind: kind, u: u, last: index == recent.count - 1)
                }
            }
            Text(kind == .weight
                 ? String(localized: "Weigh-ins are shared with Fuel, which plans your weight goal from the latest one. Touch and hold an entry to delete it.")
                 : String(localized: "Touch and hold an entry to delete it."))
                .font(HoopFont.caption)
                .foregroundStyle(HoopColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, HoopSpace.s)
        }
    }

    @ViewBuilder
    private func entryRow(_ p: HoopVitalPoint, kind: HoopManualVital, u: HoopVitalUnits, last: Bool) -> some View {
        let t = vital.text(p.value, diastolic: p.value2, u)
        // "Today, 10:44", "Mon, 08:10", "12 Sep, 21:40": short enough to stay on one line.
        let day = HoopVitalDates.relative(p.day, today: HoopVitalDates.key(Date())).text
        let when = "\(day), \(p.date.formatted(date: .omitted, time: .shortened))"
        let row = HoopRowContainer(last: last) {
            HStack(spacing: HoopSpace.m) {
                Text(when)
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                Spacer(minLength: HoopSpace.s)
                HoopValue(value: t.value, unit: t.unit, font: HoopFont.value(.body), unitFont: HoopFont.caption)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(when), \(t.spoken)")
        row
            .contextMenu {
                Button(role: .destructive) { delete(p, kind: kind) } label: { Label("Delete", systemImage: "trash") }
            }
            .accessibilityAction(named: "Delete") { delete(p, kind: kind) }
    }

    private func delete(_ p: HoopVitalPoint, kind: HoopManualVital) {
        guard let id = UUID(uuidString: p.id) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            // Weight lives in Fuel's weigh-ins (see HoopVitalsStore); everything else in the vitals log.
            if kind == .weight { plan.removeWeighIn(id) } else { log.remove(id) }
        }
    }
}

/// Average, lowest and highest over a chart window, on the reader's scale.
struct HoopVitalStats {
    let average: HoopVitalText
    let lowest: HoopVitalText
    let highest: HoopVitalText

    init(vital: HoopVital, points: [HoopVitalPoint], units u: HoopVitalUnits) {
        guard !points.isEmpty else {
            average = .none; lowest = .none; highest = .none
            return
        }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(max(xs.count, 1)) }
        if vital.manual == .bloodPressure {
            // Readings are pairs, so the lowest and highest are whole readings, ranked by systolic.
            let dia = points.compactMap(\.value2)
            average = vital.text(mean(points.map(\.value)), diastolic: dia.isEmpty ? nil : mean(dia), u)
            let low = points.min { $0.value < $1.value } ?? points[0]
            let high = points.max { $0.value < $1.value } ?? points[0]
            lowest = vital.text(low.value, diastolic: low.value2, u)
            highest = vital.text(high.value, diastolic: high.value2, u)
        } else {
            let values = points.map { vital.display($0.value, u) }
            let signed = vital.isDeviation(points[points.count - 1].value)
            average = vital.formatted(display: mean(values), signed: signed, u)
            lowest = vital.formatted(display: values.min() ?? 0, signed: signed, u)
            highest = vital.formatted(display: values.max() ?? 0, signed: signed, u)
        }
    }
}

/// The detail chart, on the reader's scale: a line (a bar a day for daily totals), a dashed average, and
/// the reading under a finger. Swift Charts gives VoiceOver each point and an audio graph.
struct HoopVitalChart: View {
    let vital: HoopVital
    let points: [HoopVitalPoint]
    let units: HoopVitalUnits
    let range: HoopVitalRange
    let tint: Color
    let average: Double?
    let selected: HoopVitalPoint?
    @Binding var selection: Date?

    private var bars: Bool { vital.cadence == .dailyTotal }
    private var dayKeyed: Bool { vital.manual == nil }
    private var isPressure: Bool { vital.manual == .bloodPressure }
    private var showPoints: Bool { vital.cadence == .occasional || points.count <= 31 }

    var body: some View {
        let yDomain = self.yDomain
        Chart {
            ForEach(points) { p in
                marks(p, floor: yDomain.lowerBound)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(HoopColor.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .accessibilityHidden(true)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.plotDate(dayKeyed: dayKeyed)))
                    .foregroundStyle(HoopColor.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                if !bars && !isPressure {
                    PointMark(x: .value("Selected", selected.plotDate(dayKeyed: dayKeyed)),
                              y: .value(vital.title, vital.display(selected.value, units)))
                        .foregroundStyle(tint)
                        .symbolSize(80)
                        .accessibilityHidden(true)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: xStride) { _ in
                AxisGridLine().foregroundStyle(HoopColor.hairline)
                // A week's weekday letters sit under their day, where its point is drawn (mid-day).
                AxisValueLabel(format: xFormat, centered: range == .week && dayKeyed)
                    .font(HoopFont.caption2)
                    .foregroundStyle(HoopColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(HoopColor.hairline)
                AxisValueLabel {
                    if let d = value.as(Double.self) { Text(axisText(d)) }
                }
                .font(HoopFont.caption2)
                .foregroundStyle(HoopColor.textTertiary)
            }
        }
        .chartXSelection(value: $selection)
    }

    @ChartContentBuilder
    private func marks(_ p: HoopVitalPoint, floor: Double) -> some ChartContent {
        let x = p.plotDate(dayKeyed: dayKeyed)
        let y = vital.display(p.value, units)
        if bars {
            BarMark(x: .value("Day", p.date, unit: .day), y: .value(vital.title, y))
                .foregroundStyle(tint.opacity(selected == nil || selected?.id == p.id ? 0.9 : 0.4))
                .cornerRadius(3)
                .accessibilityLabel(accessibilityDate(p))
                .accessibilityValue(accessibilityValue(p))
        } else if isPressure {
            LineMark(x: .value("Date", x), y: .value("Pressure", y), series: .value("Reading", "Systolic"))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(accessibilityDate(p))
                .accessibilityValue(accessibilityValue(p))
            PointMark(x: .value("Date", x), y: .value("Pressure", y))
                .foregroundStyle(tint)
                .symbolSize(24)
                .accessibilityHidden(true)
            if let dia = p.value2 {
                LineMark(x: .value("Date", x), y: .value("Pressure", dia), series: .value("Reading", "Diastolic"))
                    .foregroundStyle(tint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
                PointMark(x: .value("Date", x), y: .value("Pressure", dia))
                    .foregroundStyle(tint.opacity(0.5))
                    .symbolSize(24)
                    .accessibilityHidden(true)
            }
        } else {
            // A soft fill under a daily line; occasional readings (days or weeks apart) get the line and
            // their points only, so a gap never reads as a solid block of data.
            if vital.cadence != .occasional {
                AreaMark(x: .value("Date", x), yStart: .value("Floor", floor), yEnd: .value(vital.title, y))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                    .accessibilityHidden(true)
            }
            LineMark(x: .value("Date", x), y: .value(vital.title, y))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(accessibilityDate(p))
                .accessibilityValue(accessibilityValue(p))
            if showPoints {
                PointMark(x: .value("Date", x), y: .value(vital.title, y))
                    .foregroundStyle(tint)
                    .symbolSize(18)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Scales

    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(range.rawValue - 1), to: today) ?? today
        let end = cal.date(byAdding: .day, value: 1, to: today) ?? today
        return start...end
    }

    /// Padded so the line never rides an edge; bars start at zero; nothing but a deviation dips below 0.
    private var yDomain: ClosedRange<Double> {
        var values = points.map { vital.display($0.value, units) }
        if isPressure { values += points.compactMap(\.value2) }
        if let average { values.append(average) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if bars { return 0...max(hi * 1.15, 1) }
        let minSpan = vital.isMinutes ? 30 : max(abs(hi) * 0.04, 2 * pow(10, -Double(vital.decimals(units))))
        let half = max(hi - lo, minSpan) / 2 * 1.3
        let mid = (hi + lo) / 2
        let canGoNegative = vital.key == "skin_temp" && lo < 0
        var lower = canGoNegative ? mid - half : max(0, mid - half)
        var upper = mid + half
        if vital.unitLabel(units) == "%" { upper = min(upper, 100); lower = min(lower, upper - minSpan) }
        if upper <= lower { upper = lower + 1 }
        return lower...upper
    }

    private var xStride: AxisMarkValues {
        switch range {
        case .week: return .stride(by: .day)
        case .month: return .stride(by: .weekOfYear)
        case .quarter: return .stride(by: .month)
        }
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .week: return .dateTime.weekday(.narrow)
        case .month: return .dateTime.day().month(.abbreviated)
        case .quarter: return .dateTime.month(.abbreviated)
        }
    }

    private func axisText(_ d: Double) -> String {
        if vital.isMinutes {
            let m = Int(d.rounded())
            return m % 60 == 0 ? "\(m / 60)h" : HoopVital.minutesText(Double(m))
        }
        let signed = points.last.map { vital.isDeviation($0.value) } ?? false
        return HoopVital.decimal(d, vital.decimals(units), signed: signed)
    }

    private func accessibilityDate(_ p: HoopVitalPoint) -> String {
        dayKeyed
            ? p.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : p.date.formatted(date: .long, time: .shortened)
    }

    private func accessibilityValue(_ p: HoopVitalPoint) -> String {
        vital.text(p.value, diastolic: p.value2, units).spoken
    }
}
#endif
