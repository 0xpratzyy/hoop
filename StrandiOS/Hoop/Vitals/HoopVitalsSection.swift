#if os(iOS)
import SwiftUI

/// Pushes a vital's detail from Today.
struct HoopVitalRoute: Hashable {
    let id: String
}

/// Opens the log sheet, optionally on one kind.
struct HoopVitalLogRequest: Identifiable {
    let id = UUID()
    var kind: HoopManualVital? = nil
}

/// Today's vitals: the ones the person chose, in their order, each with its latest reading, a small
/// sparkline and how it compares with the week. Edit picks and orders them; a tap opens the chart.
struct HoopVitalsSection: View {
    let snapshot: HoopTodaySnapshot

    @EnvironmentObject private var repo: Repository
    @ObservedObject private var log = HoopVitalsLog.shared
    @ObservedObject private var plan = CutPlanStore.shared

    @AppStorage(HoopVitalsPrefs.shownKey) private var shownRaw = HoopVitalsPrefs.defaultRaw
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @AppStorage(HoopVitalsPrefs.glucoseUnitKey) private var glucoseRaw = HoopGlucoseUnit.regionalDefault.rawValue

    /// Series for the NOOP metrics on show, by vital id, and which of them have loaded.
    @State private var series: [String: [HoopVitalPoint]] = [:]
    @State private var loadedIDs: Set<String> = []
    @State private var showEditor = false
    @State private var logRequest: HoopVitalLogRequest?

    private var units: HoopVitalUnits {
        HoopVitalUnits(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw,
                       effortRaw: effortScaleRaw, glucoseRaw: glucoseRaw)
    }

    var body: some View {
        let vitals = HoopVitalsPrefs.decode(shownRaw).compactMap(HoopVitalCatalog.vital(id:))
        let u = units
        VStack(spacing: 0) {
            HoopSectionHeader("Vitals") {
                Button("Edit") { showEditor = true }
                    .font(HoopFont.subhead.weight(.semibold))
                    .foregroundStyle(HoopColor.textSecondary)
                    .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                    .accessibilityLabel("Edit vitals")
            }
            HoopGroup {
                if vitals.isEmpty { emptyRow }
                ForEach(vitals) { v in
                    let summary = HoopVitalResolver.summary(v, points: points(for: v), snapshot: snapshot, units: u)
                    NavigationLink(value: HoopVitalRoute(id: v.id)) {
                        HoopVitalRow(summary: summary, ready: ready(v))
                    }
                    .buttonStyle(HoopRowButtonStyle())
                    .accessibilityLabel(HoopVitalRow.accessibilityText(summary, ready: ready(v)))
                    .accessibilityHint("Opens the chart and what it means")
                }
                Button { logRequest = HoopVitalLogRequest() } label: { logRow }
                    .buttonStyle(HoopRowButtonStyle())
                    .accessibilityHint("Opens a form to log a reading")
            }
        }
        .task(id: loadKey(vitals)) { await load(vitals) }
        .navigationDestination(for: HoopVitalRoute.self) { route in
            if let v = HoopVitalCatalog.vital(id: route.id) {
                HoopVitalDetailView(vital: v, snapshot: snapshot,
                                    preloaded: loadedIDs.contains(v.id) ? series[v.id] : nil)
            }
        }
        .sheet(isPresented: $showEditor) { HoopVitalsEditor() }
        .sheet(item: $logRequest) { HoopLogVitalSheet(initial: $0.kind) }
    }

    private func points(for v: HoopVital) -> [HoopVitalPoint] {
        if let kind = v.manual { return HoopVitalsLoader.manualPoints(kind, log: log, plan: plan) }
        return series[v.id] ?? []
    }

    /// A row's caption waits for its data rather than flashing "No data yet" on the way in.
    private func ready(_ v: HoopVital) -> Bool {
        v.manual != nil || (snapshot.loaded && loadedIDs.contains(v.id))
    }

    private func loadKey(_ vitals: [HoopVital]) -> String {
        "\(repo.refreshSeq)|\(Repository.localDayKey(Date()))|" + vitals.map(\.id).joined(separator: ",")
    }

    private func load(_ vitals: [HoopVital]) async {
        var out: [String: [HoopVitalPoint]] = [:]
        for v in vitals {
            guard let m = v.metric else { continue }
            out[v.id] = await HoopVitalsLoader.metricPoints(m, repo: repo)
            if Task.isCancelled { return }
        }
        series = out
        loadedIDs = Set(out.keys)
    }

    private var emptyRow: some View {
        HoopRowContainer {
            VStack(alignment: .leading, spacing: 2) {
                Text("No vitals on Today")
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                Text("Tap Edit to choose which ones to show.")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var logRow: some View {
        HoopRowContainer(last: true) {
            HStack(spacing: HoopSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log a vital")
                        .font(HoopFont.body)
                        .foregroundStyle(HoopColor.text)
                    Text("Weight, blood pressure, glucose and more")
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: HoopSpace.s)
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One vital: its name and how it compares, a small sparkline, and the latest reading.
struct HoopVitalRow: View {
    let summary: HoopVitalSummary
    /// False until the row's data has loaded; the caption holds its line rather than guessing.
    var ready = true
    var last = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the value moves under the title and the sparkline goes, as in HoopRow.
        let stacked = typeSize.isAccessibilitySize
        let showSpark = ready && !stacked && summary.spark.compactMap { $0 }.count >= 2
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: HoopSpace.m))
        HoopRowContainer(last: last) {
            HStack(spacing: HoopSpace.s) {
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.vital.title)
                            .font(HoopFont.body)
                            .foregroundStyle(HoopColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        caption
                    }
                    // The name takes whatever the sparkline and value leave; the value column has a fixed
                    // minimum, so the sparklines line up down the group.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if showSpark {
                        HoopSparkline(values: summary.spark, tint: HoopColor.textTertiary, lineWidth: 1.5)
                            .frame(width: 44, height: 22)
                    }
                    HoopValue(value: ready ? summary.text.value : HoopFormat.dash, unit: summary.text.unit,
                              font: HoopFont.value(.title3))
                        .frame(minWidth: stacked ? 0 : 72, alignment: .trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if !ready {
            Text(verbatim: " ").font(HoopFont.footnote)
        } else if summary.carried {
            // The same "clock" mark the recovery hero uses for a carried score.
            Text("\(Image(systemName: "clock.arrow.circlepath")) \(summary.caption)")
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(summary.caption)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What VoiceOver reads for a row: name, reading with its unit spelled out, then the caption.
    static func accessibilityText(_ s: HoopVitalSummary, ready: Bool = true) -> String {
        guard ready else { return String(localized: "\(s.vital.title), loading") }
        let caption = s.spokenCaption.replacingOccurrences(of: " · ", with: ", ")
        return "\(s.vital.title), \(s.text.spoken). \(caption)"
    }
}
#endif
