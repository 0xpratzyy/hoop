#if os(iOS)
import StrandAnalytics
import StrandDesign
import SwiftUI

// MARK: - Sport picker

/// Every activity NOOP knows, searchable, with the most common first.
struct HoopSportPicker: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var sports: [WorkoutCatalog.Sport] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? WorkoutCatalog.all : WorkoutCatalog.matching(query)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sports) { sport in
                    Button { onPick(sport.name) } label: {
                        HStack(spacing: HoopSpace.m) {
                            Image(systemName: WorkoutTypeIconography.systemSymbolName(for: sport.name))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(HoopColor.textSecondary)
                                .frame(width: 28)
                            Text(sport.name)
                                .foregroundStyle(HoopColor.text)
                            Spacer()
                            if sport.isDistanceSport {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                    .foregroundStyle(HoopColor.textTertiary)
                                    .accessibilityLabel("Records a route")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("Start an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationBackground(HoopColor.canvas)
    }
}

// MARK: - Workout bar

/// The running gym session or activity, above the tab bar on every tab. Tap to reopen it.
struct HoopWorkoutBar: View {
    let openActivity: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var liftSession: LiftSessionController
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var body: some View {
        Button(action: open) {
            HStack(spacing: HoopSpace.m) {
                HoopLiveDot(tint: liftSession.isActive ? HoopColor.strain : HoopColor.heart)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(HoopFont.subhead.weight(.semibold))
                        .foregroundStyle(HoopColor.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: HoopSpace.s)
                if let bpm = liveBpm {
                    HoopValue(value: "\(bpm)", unit: "bpm", font: HoopFont.value(.headline), color: HoopColor.heart)
                }
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textTertiary)
            }
            .padding(.horizontal, HoopSpace.l)
            .padding(.vertical, 12)
            .background(Capsule().fill(HoopColor.surfaceHigh))
            .background(Capsule().fill(HoopColor.canvas))
        }
        .buttonStyle(HoopPressStyle())
        .accessibilityHint("Opens the running workout")
    }

    private var liveBpm: Int? {
        guard live.connected else { return nil }
        if let b = model.bpm, b > 0 { return b }
        if let h = live.heartRate, h > 0 { return h }
        return nil
    }

    private var title: String {
        if liftSession.isActive {
            let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
            return liftSession.presentation(system: system)?.exercise ?? String(localized: "Gym session")
        }
        return model.activeWorkout?.sport ?? ""
    }

    private var subtitle: String {
        if liftSession.isActive {
            let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
            return liftSession.presentation(system: system)?.status ?? String(localized: "In progress")
        }
        return model.activeWorkout?.isPaused == true ? String(localized: "Paused") : String(localized: "Tracking live")
    }

    private func open() {
        if liftSession.isActive { liftSession.isPresented = true } else { openActivity() }
    }
}

// MARK: - Live activity

/// A running activity: elapsed time, heart rate and its zone, strain so far, and the controls. The
/// workout keeps recording when this screen is closed; reopen it from Train.
struct HoopLiveActivityView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    private var effortScale: EffortScale { EffortScale(rawValue: effortScaleRaw) ?? .whoop }

    @State private var armed = false
    @State private var confirmDiscard = false
    @State private var confirmEnd = false

    private var bpm: Int? {
        guard live.connected else { return nil }
        if let b = model.bpm, b > 0 { return b }
        if let h = live.heartRate, h > 0 { return h }
        return nil
    }

    var body: some View {
        ZStack {
            HoopBackground()
            if let w = model.activeWorkout {
                content(w)
            } else {
                finished
            }
        }
        .onAppear {
            guard !armed else { return }
            armed = true
            model.startRealtimeHR()
        }
        .onDisappear {
            if armed { model.stopRealtimeHR(); armed = false }
        }
        .confirmationDialog("Discard this activity?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                model.discardWorkout()
                dismiss()
            }
        } message: {
            Text("Nothing from this activity will be saved.")
        }
        .confirmationDialog("End and save?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End activity") {
                model.endWorkout()
                dismiss()
            }
        } message: {
            if let w = model.activeWorkout, AppModel.isTooShortToSave(elapsedSeconds: elapsed(w, at: Date())) {
                Text("This activity is too short to save, so it will be discarded.")
            } else {
                Text("Hoop saves it with its heart rate, strain and calories.")
            }
        }
    }

    private func elapsed(_ w: AppModel.ActiveWorkout, at now: Date) -> TimeInterval {
        let end = w.pausedAt ?? now
        return max(0, end.timeIntervalSince(w.start) - w.pausedDuration)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func content(_ w: AppModel.ActiveWorkout) -> some View {
        let zone = bpm.map { HoopZone.of(bpm: $0, hrMax: profile.hrMax) }
        return VStack(spacing: 0) {
            HStack {
                Label(w.sport, systemImage: WorkoutTypeIconography.systemSymbolName(for: w.sport))
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.text)
                Spacer()
                HoopIconButton(systemName: "chevron.down", label: "Minimise") { dismiss() }
            }
            .hoopScreenPadding()
            .padding(.top, HoopSpace.s)

            Spacer(minLength: HoopSpace.l)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(clock(elapsed(w, at: ctx.date)))
                    .font(HoopFont.number(76))
                    .foregroundStyle(w.isPaused ? HoopColor.textSecondary : HoopColor.text)
                    .contentTransition(.numericText())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityLabel("Elapsed time")
            Text(w.isPaused ? "Paused" : "Elapsed")
                .font(HoopFont.subhead)
                .foregroundStyle(HoopColor.textSecondary)

            ZStack {
                HoopGlow(tint: zone?.color ?? HoopColor.heart, intensity: 0.2).frame(width: 360, height: 360)
                VStack(spacing: 4) {
                    HoopHeroNumber(value: bpm.map(String.init) ?? HoopFormat.dash, symbol: bpm == nil ? "" : "bpm", size: 64,
                                   color: bpm == nil ? HoopColor.textTertiary : HoopColor.text)
                    Text(zone?.label ?? (live.connected ? String(localized: "Waiting for heart rate") : String(localized: "Strap not connected")))
                        .font(HoopFont.subhead)
                        .foregroundStyle(zone?.color ?? HoopColor.textSecondary)
                }
            }
            .frame(height: 220)

            HStack(spacing: 0) {
                HoopStat(label: "Strain", value: String(format: "%.1f", UnitFormatter.effortValue(w.liveStrain, scale: effortScale)))
                HoopStat(label: "Average", value: w.avgHr > 0 ? "\(w.avgHr)" : HoopFormat.dash, unit: w.avgHr > 0 ? "bpm" : "")
                HoopStat(label: "Peak", value: w.peakHr > 0 ? "\(w.peakHr)" : HoopFormat.dash, unit: w.peakHr > 0 ? "bpm" : "")
            }
            .hoopScreenPadding()

            Spacer(minLength: HoopSpace.l)

            HStack(spacing: HoopSpace.m) {
                Button { model.toggleWorkoutPause() } label: {
                    Label(w.isPaused ? "Resume" : "Pause", systemImage: w.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(HoopSecondaryButtonStyle())
                Button { confirmEnd = true } label: {
                    Label("End", systemImage: "stop.fill")
                }
                .buttonStyle(HoopPrimaryButtonStyle(tint: HoopColor.heart))
            }
            .hoopScreenPadding()
            Button("Discard") { confirmDiscard = true }
                .font(HoopFont.subhead)
                .foregroundStyle(HoopColor.textSecondary)
                .padding(.top, HoopSpace.m)
                .padding(.bottom, HoopSpace.l)
        }
    }

    private var finished: some View {
        VStack(spacing: HoopSpace.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(HoopColor.recoveryHigh)
            Text("Activity saved")
                .font(HoopFont.title)
                .foregroundStyle(HoopColor.text)
            Text("It appears in Train and counts toward today's strain.")
                .font(HoopFont.callout)
                .foregroundStyle(HoopColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(HoopPrimaryButtonStyle())
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.l)
        }
        .hoopScreenPadding()
    }
}
#endif
