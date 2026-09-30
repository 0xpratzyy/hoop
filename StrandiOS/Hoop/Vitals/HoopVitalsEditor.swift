#if os(iOS)
import SwiftUI

/// Choose which vitals Today shows, and in what order. The chosen ones sit at the top to drag into order;
/// below, every vital Hoop can show, grouped, with a switch each. In each group the ones holding data come
/// first; the rest are marked and can still be switched on, ready for when data arrives.
struct HoopVitalsEditor: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var log = HoopVitalsLog.shared
    @ObservedObject private var plan = CutPlanStore.shared
    @AppStorage(HoopVitalsPrefs.shownKey) private var shownRaw = HoopVitalsPrefs.defaultRaw
    @Environment(\.dismiss) private var dismiss

    /// NOOP metric ids holding at least one reading; nil while that's being checked.
    @State private var withData: Set<String>?
    @State private var logRequest: HoopVitalLogRequest?

    var body: some View {
        let ids = HoopVitalsPrefs.decode(shownRaw)
        let shown = ids.compactMap(HoopVitalCatalog.vital(id:))
        NavigationStack {
            List {
                Section {
                    if shown.isEmpty {
                        Text("Nothing on Today yet. Switch on the vitals you want below.")
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                    ForEach(shown) { v in
                        onTodayRow(v)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { setShown(v.id, false) } label: { Text("Hide") }
                            }
                            // Dragging has no VoiceOver equivalent, so the same moves are actions.
                            .accessibilityAction(named: "Move up") { move(v.id, by: -1) }
                            .accessibilityAction(named: "Move down") { move(v.id, by: 1) }
                            .accessibilityAction(named: "Hide") { setShown(v.id, false) }
                    }
                    // Touch and hold, then drag: List reorders without an edit mode, which would also
                    // switch off every toggle below.
                    .onMove { from, to in
                        var next = ids
                        next.move(fromOffsets: from, toOffset: to)
                        shownRaw = HoopVitalsPrefs.encode(next)
                    }
                } header: {
                    Text("On Today")
                } footer: {
                    Text("Touch and hold a vital, then drag it into place. Swipe left to hide it.")
                }

                ForEach(HoopVitalCategory.allCases) { category in
                    let vitals = listed(in: category)
                    if !vitals.isEmpty {
                        Section {
                            ForEach(vitals) { v in
                                toggleRow(v, on: ids.contains(v.id))
                            }
                            if category == .logged {
                                Button { logRequest = HoopVitalLogRequest() } label: {
                                    Label("Log a vital", systemImage: "plus")
                                }
                            }
                        } header: {
                            Text(category.title)
                        } footer: {
                            if category == .logged {
                                Text("Readings you log stay on this iPhone. Weight is the same list as Fuel's weigh-ins, so the two always agree.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit vitals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task { withData = await repo.nonEmptyMetricIDs(HoopVitalCatalog.all.compactMap(\.metric)) }
            .sheet(item: $logRequest) { HoopLogVitalSheet(initial: $0.kind) }
        }
    }

    /// A group's vitals: those with data first, then the rest, each in catalog order. A Mi Band copy is
    /// only listed once it holds data.
    private func listed(in category: HoopVitalCategory) -> [HoopVital] {
        let vitals = HoopVitalCatalog.all.filter { v in
            v.category == category && (!HoopVitalCatalog.listedOnlyWithData(v) || hasData(v) == true)
        }
        return vitals.filter { hasData($0) != false } + vitals.filter { hasData($0) == false }
    }

    /// nil while the check runs, so nothing is marked empty before it's known.
    private func hasData(_ v: HoopVital) -> Bool? {
        if let kind = v.manual {
            return kind == .weight ? !plan.weighIns.isEmpty : !log.entries(for: kind).isEmpty
        }
        return withData.map { $0.contains(v.id) }
    }

    private func onTodayRow(_ v: HoopVital) -> some View {
        HStack(spacing: HoopSpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.title)
                    .foregroundStyle(HoopColor.text)
                Text(v.category.title)
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textSecondary)
            }
            Spacer(minLength: HoopSpace.s)
            // A grip, so the rows read as something to drag.
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(HoopColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func move(_ id: String, by offset: Int) {
        var next = HoopVitalsPrefs.decode(shownRaw)
        guard let i = next.firstIndex(of: id) else { return }
        let j = i + offset
        guard next.indices.contains(j) else { return }
        next.swapAt(i, j)
        shownRaw = HoopVitalsPrefs.encode(next)
    }

    /// The whole row is the switch: a tap anywhere on it shows or hides the vital, and the switch mirrors
    /// the state. A larger target than the switch alone, and one control for VoiceOver.
    private func toggleRow(_ v: HoopVital, on: Bool) -> some View {
        let note = note(v)
        return Button { setShown(v.id, !on) } label: {
            HStack(spacing: HoopSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.title)
                        .foregroundStyle(HoopColor.text)
                    if let note {
                        Text(note)
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                }
                Spacer(minLength: HoopSpace.s)
                Toggle(v.title, isOn: .constant(on))
                    .labelsHidden()
                    // Hoop's accent is near-white, which would hide the knob; on is the recovery green.
                    .tint(HoopColor.recoveryHigh)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.map { "\(v.title), \($0)" } ?? v.title)
        .accessibilityValue(on ? String(localized: "On Today") : String(localized: "Hidden"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(on ? String(localized: "Removes it from Today") : String(localized: "Adds it to Today"))
    }

    /// The source when it isn't the strap, and whether there's anything to show yet.
    private func note(_ v: HoopVital) -> String? {
        var parts: [String] = []
        // The source, unless the name already carries it ("Weight (Apple Health)").
        if let m = v.metric, m.source != Repository.whoopSource, !v.title.contains(m.sourceLabel) {
            parts.append(m.sourceLabel)
        }
        if hasData(v) == false {
            parts.append(v.manual != nil ? String(localized: "Nothing logged yet") : String(localized: "No data yet"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func setShown(_ id: String, _ on: Bool) {
        var next = HoopVitalsPrefs.decode(shownRaw)
        if on {
            if !next.contains(id) { next.append(id) }
        } else {
            next.removeAll { $0 == id }
        }
        shownRaw = HoopVitalsPrefs.encode(next)
    }
}
#endif
