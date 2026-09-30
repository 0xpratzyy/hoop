#if os(iOS)
import StrandDesign
import SwiftUI
import WhoopStore

/// Train: the gym tracker and every other activity. Say what you're training in plain words and Hoop
/// lays out the session (typed sets parse on the device; a description goes to Hoop AI), then the gym
/// session runs set by set with rest timers and a strap double-tap to finish a set. Any other activity
/// starts from the sport list with live heart rate and strain.
struct HoopTrainView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var liftSession: LiftSessionController
    @ObservedObject private var ai = HoopAI.shared
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var effortScale: EffortScale { EffortScale(rawValue: effortScaleRaw) ?? .whoop }

    @State private var request = ""
    @State private var plan: HoopTrainPlan?
    @State private var planning = false
    @State private var planError: String?
    @State private var recent: [WorkoutRow] = []
    @State private var showSports = false
    @State private var showLive = false
    @State private var showConnect = false
    @FocusState private var requestFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if liftSession.isActive { resumeGym.padding(.top, HoopSpace.s) }
                    if model.activeWorkout != nil { resumeActivity.padding(.top, HoopSpace.s) }
                    planner.padding(.top, HoopSpace.s)
                    if let plan { planPreview(plan).padding(.top, HoopSpace.m) }
                    quickStart.padding(.top, HoopSpace.l)
                    HoopSectionHeader("This week")
                    weekStats
                    if !recent.isEmpty {
                        HoopSectionHeader("Recent")
                        recentList
                    }
                    HoopGroupLabel("More")
                    HoopGroup {
                        NavigationLink(value: HoopTrainRoute.programs) {
                            HoopRow(title: "Programs & gym history", subtitle: String(localized: "Saved routines, sets per muscle, past sessions"), chevron: true)
                        }
                        .buttonStyle(HoopRowButtonStyle())
                        NavigationLink(value: HoopTrainRoute.workouts) {
                            HoopRow(title: "All workouts", chevron: true, last: true)
                        }
                        .buttonStyle(HoopRowButtonStyle())
                    }
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .hoopTabRoot("Train")
            .hoopNavigationSubtitle(HoopFormat.longDate())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HoopAskButton(topic: .train) }
            }
            .navigationDestination(for: HoopTrainRoute.self) { route in
                route.destination.navigationBarTitleDisplayMode(.inline)
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .onChange(of: repo.refreshSeq) { _, _ in Task { await load() } }
        .onChange(of: liftSession.savedSessions) { _, _ in Task { await load() } }
        .sheet(isPresented: $showSports) {
            HoopSportPicker { sport in
                showSports = false
                model.startWorkout(sport: sport)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showLive = true }
            }
        }
        .fullScreenCover(isPresented: $showLive) { HoopLiveActivityView() }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
    }

    // MARK: Resume

    private var resumeGym: some View {
        Button { liftSession.isPresented = true } label: {
            HoopSurface {
                HStack(spacing: HoopSpace.m) {
                    HoopLiveDot(tint: HoopColor.strain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gym session in progress")
                            .font(HoopFont.headline)
                            .foregroundStyle(HoopColor.text)
                        if let p = liftSession.presentation(system: system) {
                            Text("\(p.exercise) · \(p.status)")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("Resume").font(HoopFont.callout.weight(.semibold)).foregroundStyle(HoopColor.strain)
                }
            }
        }
        .buttonStyle(HoopPressStyle())
    }

    private var resumeActivity: some View {
        Button { showLive = true } label: {
            HoopSurface {
                HStack(spacing: HoopSpace.m) {
                    HoopLiveDot(tint: HoopColor.heart)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(model.activeWorkout?.sport ?? "") in progress")
                            .font(HoopFont.headline)
                            .foregroundStyle(HoopColor.text)
                        Text(model.activeWorkout?.isPaused == true ? "Paused" : "Tracking live")
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                    Spacer()
                    Text("Open").font(HoopFont.callout.weight(.semibold)).foregroundStyle(HoopColor.heart)
                }
            }
        }
        .buttonStyle(HoopPressStyle())
    }

    // MARK: Planner

    private var planner: some View {
        HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HStack(spacing: 6) {
                    HoopAIGlyph(size: 13)
                    Text("What are you training today?")
                        .font(HoopFont.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textSecondary)
                }
                TextField("Push day, 45 min, dumbbells only\nor: Bench 4x8 60kg, OHP 3x10 40kg", text: $request, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($requestFocused)
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                if let planError {
                    Text(planError)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.recoveryLow)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: HoopSpace.m) {
                    ForEach(starters, id: \.self) { s in
                        Button { request = s; makePlan() } label: {
                            Text(s)
                                .font(HoopFont.footnote)
                                .foregroundStyle(HoopColor.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(HoopColor.surfaceHigh))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(request.isEmpty && plan == nil ? 1 : 0)
                .frame(height: request.isEmpty && plan == nil ? nil : 0)
                .clipped()
                Button(action: makePlan) {
                    HStack(spacing: HoopSpace.s) {
                        if planning { ProgressView().tint(HoopColor.canvas) }
                        Text(planning ? "Planning…" : "Show me what to do")
                    }
                }
                .buttonStyle(HoopPrimaryButtonStyle())
                .disabled(planning || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var starters: [String] {
        [String(localized: "Upper body"), String(localized: "Legs"), String(localized: "Full body, 30 min")]
    }

    private func makePlan() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        requestFocused = false
        planError = nil
        // Explicit sets and reps are read on the device: no AI needed to run a session you already know.
        if let parsed = HoopTrainParser.parse(text, system: system) {
            withAnimation(.snappy) { plan = parsed }
            return
        }
        guard ai.isConnected else {
            planError = String(localized: "Write sets like \"Bench 4x8 60kg\", or connect Hoop AI to plan from a description.")
            showConnect = true
            return
        }
        planning = true
        Task {
            defer { planning = false }
            do {
                let snap = await HoopTodayLoader.load(repo: repo, profile: profile)
                var context = HoopAIContext.build(repo: repo, profile: profile, snapshot: snap)
                context += await recentTrainingContext()
                let p = try await ai.planWorkout(text, context: context, system: system)
                withAnimation(.snappy) { plan = p }
            } catch {
                planError = error.localizedDescription
            }
        }
    }

    private func recentTrainingContext() async -> String {
        guard !recent.isEmpty else { return "" }
        let lines = recent.prefix(8).map { w -> String in
            let day = Date(timeIntervalSince1970: TimeInterval(w.startTs)).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let mins = Int(((w.durationS ?? Double(w.endTs - w.startTs)) / 60).rounded())
            let strain = w.strain.map { String(format: "%.1f", UnitFormatter.effortValue($0, scale: .whoop)) } ?? "-"
            return "\(day): \(w.sport), \(mins) min, strain \(strain)"
        }
        return "\n\nRecent workouts:\n" + lines.joined(separator: "\n")
    }

    // MARK: Plan preview

    private func planPreview(_ p: HoopTrainPlan) -> some View {
        HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                            .font(HoopFont.title3)
                            .foregroundStyle(HoopColor.text)
                        Text(planMeta(p))
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { plan = nil } } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HoopColor.textTertiary)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard plan")
                }
                if let summary = p.summary, !summary.isEmpty {
                    Text(summary)
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(Array(p.exercises.enumerated()), id: \.element.id) { i, e in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: HoopSpace.s) {
                                Text("\(i + 1)")
                                    .font(HoopFont.value(.footnote))
                                    .foregroundStyle(HoopColor.textTertiary)
                                    .frame(width: 18, alignment: .leading)
                                Text(e.name)
                                    .font(HoopFont.body.weight(.semibold))
                                    .foregroundStyle(HoopColor.text)
                            }
                            Text(e.summary(system: system))
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                                .padding(.leading, 26)
                            if let note = e.note {
                                Text(note)
                                    .font(HoopFont.footnote)
                                    .foregroundStyle(HoopColor.textTertiary)
                                    .padding(.leading, 26)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if i < p.exercises.count - 1 { HoopDivider().padding(.leading, 26) }
                        }
                    }
                }
                Button {
                    startGym(p)
                } label: {
                    Text(liftSession.isActive ? "Session already running" : "Start session")
                }
                .buttonStyle(HoopPrimaryButtonStyle(tint: HoopColor.strain))
                .disabled(liftSession.isActive)
                Text("During the session, double-tap your strap to finish a set and start the rest timer.")
                    .font(HoopFont.caption)
                    .foregroundStyle(HoopColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func planMeta(_ p: HoopTrainPlan) -> String {
        let exercises = p.exercises.count == 1 ? String(localized: "1 exercise") : String(localized: "\(p.exercises.count) exercises")
        var bits = [exercises, String(localized: "\(p.totalSets) sets")]
        if let m = p.minutes { bits.append("~\(m) min") }
        if p.fromAI { bits.append(String(localized: "planned by Hoop AI")) }
        return bits.joined(separator: " · ")
    }

    private func startGym(_ p: HoopTrainPlan) {
        guard !liftSession.isActive else { liftSession.isPresented = true; return }
        liftSession.start(plan: p.liftPlan, programId: nil, programName: p.name)
        withAnimation(.snappy) { plan = nil; request = "" }
    }

    // MARK: Quick start

    private var quickStart: some View {
        HStack(spacing: HoopSpace.m) {
            Button {
                if liftSession.isActive { liftSession.isPresented = true }
                else { liftSession.start(plan: [], programId: nil, programName: String(localized: "Gym session")) }
            } label: {
                startTile(icon: "dumbbell.fill", title: "Gym session", subtitle: "Log sets as you go", tint: HoopColor.strain)
            }
            .buttonStyle(HoopPressStyle())
            Button {
                if model.activeWorkout != nil { showLive = true } else { showSports = true }
            } label: {
                startTile(icon: "figure.run", title: "Activity", subtitle: "Run, ride, play…", tint: HoopColor.heart)
            }
            .buttonStyle(HoopPressStyle())
        }
    }

    private func startTile(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, tint: Color) -> some View {
        HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.s) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 26)
                Text(title).font(HoopFont.headline).foregroundStyle(HoopColor.text)
                Text(subtitle).font(HoopFont.footnote).foregroundStyle(HoopColor.textSecondary).lineLimit(1)
            }
        }
    }

    // MARK: Week + recent

    private var weekRows: [WorkoutRow] {
        let cutoff = Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
        return recent.filter { $0.startTs >= cutoff }
    }

    private var weekStats: some View {
        let rows = weekRows
        let minutes = rows.reduce(0.0) { $0 + (($1.durationS ?? Double($1.endTs - $1.startTs)) / 60) }
        let strain = rows.compactMap(\.strain).map { UnitFormatter.effortValue($0, scale: effortScale) }
        let kcal = rows.compactMap(\.energyKcal).reduce(0, +)
        return HoopSurface {
            HStack(spacing: 0) {
                HoopStat(label: "Workouts", value: "\(rows.count)")
                HoopStat(label: "Time", value: HoopFormat.hoursMinutes(minutes > 0 ? minutes : nil))
                HoopStat(label: "Top strain", value: strain.max().map { String(format: "%.1f", $0) } ?? HoopFormat.dash)
                HoopStat(label: "Calories", value: kcal > 0 ? HoopFormat.int(kcal) : HoopFormat.dash)
            }
        }
    }

    private var recentList: some View {
        HoopGroup {
            ForEach(Array(recent.prefix(6).enumerated()), id: \.offset) { i, w in
                NavigationLink {
                    WorkoutDetailView(row: w)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                HoopRowContainer(last: i == min(recent.count, 6) - 1) {
                    HStack(spacing: HoopSpace.m) {
                        Image(systemName: WorkoutTypeIconography.systemSymbolName(for: w.sport))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HoopColor.textSecondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.sport).font(HoopFont.body).foregroundStyle(HoopColor.text)
                            Text(recentLine(w)).font(HoopFont.footnote).foregroundStyle(HoopColor.textSecondary)
                        }
                        Spacer()
                        if let s = w.strain {
                            HoopValue(value: String(format: "%.1f", UnitFormatter.effortValue(s, scale: effortScale)),
                                      font: HoopFont.value(.body), color: HoopColor.strain)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HoopColor.textTertiary)
                    }
                }
                }
                .buttonStyle(HoopRowButtonStyle())
            }
        }
    }

    private func recentLine(_ w: WorkoutRow) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(w.startTs))
        let mins = (w.durationS ?? Double(w.endTs - w.startTs)) / 60
        var bits = [date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), HoopFormat.hoursMinutes(mins)]
        if let hr = w.avgHr { bits.append("\(hr) bpm") }
        return bits.joined(separator: " · ")
    }

    private func load() async {
        let rows = await repo.workoutRows(days: 60)
        recent = rows.sorted { $0.startTs > $1.startTs }
    }
}

enum HoopTrainRoute: Hashable {
    case programs, workouts

    @ViewBuilder var destination: some View {
        switch self {
        case .programs: LiftLogView()
        case .workouts: WorkoutsView()
        }
    }
}
#endif
