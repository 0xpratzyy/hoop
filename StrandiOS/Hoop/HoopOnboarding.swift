#if os(iOS)
import StrandDesign
import SwiftUI
import UIKit

// MARK: - First run

/// Hoop's first run: what it is, the honest fine print, which strap, freeing it from the WHOOP app,
/// pairing, and a short profile so calories and heart-rate zones are personal.
struct HoopOnboardingView: View {
    let onFinished: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, promise, strap, prepare, pair, profile, done
    }

    @State private var step: Step = .welcome
    @State private var accepted = false
    @State private var paired = false
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Group {
                    switch step {
                    case .welcome: HoopWelcomeStep()
                    case .promise: HoopPromiseStep(accepted: $accepted)
                    case .strap: HoopStrapChoiceStep(selection: $selectedModelRaw)
                    case .prepare: HoopPrepareStep(model: selectedModel)
                    case .pair: HoopPairStep(model: selectedModel, paired: $paired)
                    case .profile: HoopProfileStep()
                    case .done: HoopDoneStep(paired: paired)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                          removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
            // Long steps scroll out softly under the top bar instead of meeting a hard edge.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Rectangle()
                }
                .ignoresSafeArea(edges: .bottom)
            }
            // The bar stays put while steps slide, and long steps scroll softly away beneath it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .hoopScreenPadding()
                    .padding(.top, HoopSpace.xl)
                    .padding(.bottom, HoopSpace.s)
                    .background {
                        LinearGradient(stops: [.init(color: HoopColor.canvas.opacity(0), location: 0),
                                               .init(color: HoopColor.canvas, location: 0.32)],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                            .allowsHitTesting(false)
                    }
            }
        }
        // The glow is a background so its size never enters layout.
        .background {
            ZStack {
                HoopBackground()
                HoopGlow(tint: tint, intensity: 0.16)
                    .frame(width: 760, height: 760)
                    .offset(y: -420)
                    .animation(.easeInOut(duration: 0.6), value: tint)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var tint: Color {
        switch step {
        case .done: return HoopColor.recoveryHigh
        case .pair: return paired ? HoopColor.recoveryHigh : HoopColor.brandCyan
        default: return HoopColor.brandCyan
        }
    }

    private var topBar: some View {
        HStack {
            if step != .welcome {
                HoopIconButton(systemName: "chevron.left", label: "Back", size: 36) { back() }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            if step != .welcome {
                HStack(spacing: 6) {
                    ForEach(Step.allCases.dropFirst(), id: \.self) { s in
                        Capsule()
                            .fill(s.rawValue <= step.rawValue ? HoopColor.text : HoopColor.track)
                            .frame(width: s == step ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Step \(step.rawValue) of \(Step.allCases.count - 1)"))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, HoopSpace.m)
        .padding(.top, HoopSpace.xs)
    }

    private var bottomBar: some View {
        VStack(spacing: HoopSpace.xs) {
            if step != .pair || paired {
                Button(action: primary) { Text(primaryTitle) }
                    .buttonStyle(HoopPrimaryButtonStyle(tint: step == .done ? HoopColor.recoveryHigh : HoopColor.text))
                    .disabled(step == .promise && !accepted)
            }
            if step == .pair && !paired {
                Button("Skip for now") { advance() }
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return String(localized: "Get started")
        case .promise: return String(localized: "I understand")
        case .strap: return String(localized: "Continue")
        case .prepare: return String(localized: "My strap is ready")
        case .pair: return String(localized: "Continue")
        case .profile: return String(localized: "Save")
        case .done: return String(localized: "Open Hoop")
        }
    }

    private func primary() {
        if step == .done { finish(); return }
        advance()
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { finish(); return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = next }
    }

    private func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { step = prev }
    }

    private func finish() {
        // Keep the shared NOOP gates in step so none of them re-opens over Hoop.
        let d = UserDefaults.standard
        d.set(true, forKey: "noop.onboarded")
        d.set(Terms.currentVersion, forKey: "noop.acceptedTermsVersion")
        d.set(AppChangelog.currentVersion, forKey: "noop.lastSeenChangelogVersion")
        onFinished()
    }
}

// MARK: - Steps

private struct HoopStepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HoopSpace.section - 4) {
                VStack(alignment: .leading, spacing: HoopSpace.m) {
                    Text(title)
                        .font(HoopFont.largeTitle)
                        .foregroundStyle(HoopColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(HoopFont.body)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .hoopScreenPadding()
            .padding(.top, HoopSpace.xxl)
            .padding(.bottom, HoopSpace.xl)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct HoopWelcomeStep: View {
    @State private var appear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: HoopSpace.xxl)
            HoopLogoMark(size: 150, style: .glyph, drawn: appear)
            VStack(spacing: HoopSpace.m) {
                Text("Hoop")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(HoopColor.text)
                Text("Your strap. Your data.\nRight on your iPhone.")
                    .font(HoopFont.title3.weight(.regular))
                    .foregroundStyle(HoopColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 44)
            .opacity(appear ? 1 : 0)
            .offset(y: appear || reduceMotion ? 0 : 10)
            Spacer(minLength: HoopSpace.xxl)
            VStack(alignment: .leading, spacing: HoopSpace.l) {
                line("waveform.path.ecg", "Recovery, strain and sleep, scored on-device")
                line("heart", "Live heart rate straight from your strap")
                line("lock", "No account, no cloud, no subscription")
            }
            .opacity(appear ? 1 : 0)
            .padding(.bottom, HoopSpace.s)
        }
        .hoopScreenPadding()
        .onAppear {
            if reduceMotion { appear = true; return }
            withAnimation(.spring(response: 1.3, dampingFraction: 0.9).delay(0.15)) { appear = true }
        }
    }

    private func line(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: HoopSpace.l) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(HoopColor.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(HoopFont.callout)
                .foregroundStyle(HoopColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HoopPromiseStep: View {
    @Binding var accepted: Bool

    var body: some View {
        HoopStepScaffold(title: "Before you pair",
                         subtitle: "A few honest words, so nothing is a surprise.") {
            VStack(alignment: .leading, spacing: HoopSpace.xl + 2) {
                note("Independent and unofficial",
                     "Hoop is not made by, affiliated with, or endorsed by WHOOP, Inc. It talks to a strap you own over Bluetooth.")
                note("Not a medical device",
                     "Every score is an estimate for general wellness. Don't use Hoop to diagnose or treat anything.")
                note("Everything stays on this iPhone",
                     "Your data is stored and scored locally. There is no Hoop account and no Hoop server. Optional Hoop AI sends a summary to OpenAI only when you use it.")
                note("Still experimental",
                     "WHOOP 4.0 has the fullest support. On WHOOP 5.0 / MG live heart rate works well, while sleep and recovery are still improving.")
            }
            Button {
                withAnimation(.snappy) { accepted.toggle() }
            } label: {
                HStack(spacing: HoopSpace.m + 2) {
                    Image(systemName: accepted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(accepted ? HoopColor.recoveryHigh : HoopColor.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                    Text("I understand Hoop is unofficial and not medical advice.")
                        .font(HoopFont.callout.weight(.medium))
                        .foregroundStyle(HoopColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(HoopSpace.l + 2)
                .background(RoundedRectangle(cornerRadius: HoopSpace.smallRadius + 4, style: .continuous)
                    .fill(accepted ? HoopColor.surfaceHigh : HoopColor.surface))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(accepted ? [.isSelected] : [])
        }
    }

    private func note(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(HoopFont.headline)
                .foregroundStyle(HoopColor.text)
            Text(body)
                .font(HoopFont.subhead)
                .foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pick WHOOP 4.0 or 5.0 / MG. Shared by first run and the pairing sheet.
struct HoopStrapChoiceStepContent: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: HoopSpace.m) {
            ForEach(WhoopModel.allCases) { m in
                let on = selection == m.rawValue
                Button {
                    withAnimation(.snappy) { selection = m.rawValue }
                } label: {
                    HStack(alignment: .center, spacing: HoopSpace.l) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.displayName)
                                .font(HoopFont.headline)
                                .foregroundStyle(HoopColor.text)
                            Text(m == .whoop4
                                 ? "Full support: recovery, strain, sleep, live heart rate and history."
                                 : "Live heart rate and history. Sleep and recovery are experimental.")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(on ? HoopColor.text : HoopColor.textTertiary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(HoopSpace.l + 2)
                    .background(RoundedRectangle(cornerRadius: HoopSpace.smallRadius + 4, style: .continuous)
                        .fill(on ? HoopColor.surfaceHigh : HoopColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: HoopSpace.smallRadius + 4, style: .continuous)
                        .strokeBorder(on ? HoopColor.text.opacity(0.85) : Color.clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            Text("Not sure? WHOOP 4.0 has a clasp on the band and a battery pack that slides on top. WHOOP 5.0 and MG charge with a pack that clips on, and MG has a metal sensor ring.")
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, HoopSpace.s)
        }
    }
}

private struct HoopStrapChoiceStep: View {
    @Binding var selection: String
    var body: some View {
        HoopStepScaffold(title: "Which strap do you have?") {
            HoopStrapChoiceStepContent(selection: $selection)
        }
    }
}

/// How to free the strap from the WHOOP app, per model: a short numbered path.
struct HoopPrepareStepContent: View {
    let model: WhoopModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let list = steps
            ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: HoopSpace.l) {
                    VStack(spacing: 0) {
                        Text("\(i + 1)")
                            .font(HoopFont.value(.subheadline))
                            .foregroundStyle(HoopColor.text)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(HoopColor.text.opacity(0.28), lineWidth: 1))
                        if i < list.count - 1 {
                            Rectangle()
                                .fill(HoopColor.hairline)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 6)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title)
                            .font(HoopFont.headline)
                            .foregroundStyle(HoopColor.text)
                        Text(s.body)
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, i < list.count - 1 ? HoopSpace.xxl : 0)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
            HStack(alignment: .top, spacing: HoopSpace.m) {
                Image(systemName: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HoopColor.textTertiary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                Text("A WHOOP strap talks to one app at a time. While it's paired with Hoop, the official WHOOP app may need to re-pair before it can sync again.")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, HoopSpace.section - 4)
        }
    }

    private struct Line { let title: String; let body: String }

    private var steps: [Line] {
        switch model {
        case .whoop4:
            return [
                Line(title: String(localized: "Close the WHOOP app"),
                     body: String(localized: "Force-quit it (swipe it away in the app switcher) so it lets go of the strap. If you use it on another phone, turn that phone's Bluetooth off.")),
                Line(title: String(localized: "Wear it and wake it"),
                     body: String(localized: "Put the strap on, sensor against your skin, and make sure it has some charge.")),
                Line(title: String(localized: "Keep it close"),
                     body: String(localized: "Stay within about a metre of this iPhone with Bluetooth on.")),
            ]
        case .whoop5mg:
            return [
                Line(title: String(localized: "Close the WHOOP app"),
                     body: String(localized: "Force-quit it, or turn off Bluetooth on the phone that runs it, so it isn't holding the strap.")),
                Line(title: String(localized: "Put it in pairing mode"),
                     body: String(localized: "Tap the sensor firmly and repeatedly until its lights flash blue.")),
                Line(title: String(localized: "Accept the pairing request"),
                     body: String(localized: "When iOS asks to pair with your WHOOP, tap Pair. It can take a couple of tries.")),
            ]
        }
    }
}

private struct HoopPrepareStep: View {
    let model: WhoopModel
    var body: some View {
        HoopStepScaffold(title: "Free your strap",
                         subtitle: "Your strap can only talk to one app at a time, so let the WHOOP app go first.") {
            HoopPrepareStepContent(model: model)
        }
    }
}

// MARK: - Pairing

/// The scan-and-bond panel: a radar while searching, a quiet success once bonded, and calm help when
/// nothing turns up. Reports success through `paired`.
struct HoopPairPanel: View {
    let model: WhoopModel
    @Binding var paired: Bool

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var live: LiveState
    @State private var scanning = false
    @State private var attempt = 0
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: HoopSpace.xxl) {
            HoopRadar(active: scanning && !live.bonded, found: live.bonded)
                .frame(width: 240, height: 240)
                .frame(maxWidth: .infinity)
            VStack(spacing: HoopSpace.s) {
                Text(title)
                    .font(HoopFont.title)
                    .foregroundStyle(HoopColor.text)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(HoopFont.callout)
                    .foregroundStyle(HoopColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut, value: live.bonded)
            .accessibilityElement(children: .combine)

            if !live.bonded && !scanning {
                Button { startScan() } label: {
                    Text(attempt == 0 ? "Find my strap" : "Try again")
                }
                .buttonStyle(HoopPrimaryButtonStyle())
                .transition(.opacity)
            }
            if !live.bonded && showHelp {
                help.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: scanning)
        .onAppear { if !live.bonded { startScan() } else { paired = true } }
        .onChange(of: live.bonded) { _, bonded in
            if bonded {
                scanning = false
                withAnimation(.spring) { paired = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private var title: String {
        if live.bonded { return String(localized: "You're connected") }
        if live.connected { return String(localized: "Almost there…") }
        if scanning { return String(localized: "Looking for your strap") }
        return attempt == 0 ? String(localized: "Ready to pair") : String(localized: "Didn't find it yet")
    }

    private var subtitle: String {
        if live.bonded {
            if let pct = live.batteryPct { return String(localized: "\(model.displayName) paired · \(Int(pct.rounded()))% battery") }
            return String(localized: "\(model.displayName) paired and ready.")
        }
        if live.connected {
            return model == .whoop5mg
                ? String(localized: "Connected. Tap Pair if iOS asks, and keep the strap close.")
                : String(localized: "Connected. Finishing the handshake.")
        }
        if scanning { return String(localized: "Keep your strap close and awake.") }
        return String(localized: "Make sure the WHOOP app is closed, then search.")
    }

    private var help: some View {
        HoopSurface(padding: HoopSpace.l + 2) {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                Text("Not showing up? That's common.")
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.text)
                tip("The official WHOOP app is fully closed, on every phone near you.")
                if model == .whoop5mg {
                    tip("The strap is in pairing mode: tap it until the lights flash blue.")
                    tip("If iOS showed a pairing request, you tapped Pair.")
                } else {
                    tip("The strap is on your wrist and charged, so it's awake.")
                }
                tip("WHOOP straps never appear in iOS Bluetooth settings. Only apps like Hoop can find them, so don't pair there.")
            }
        }
    }

    private func tip(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HoopSpace.m) {
            Circle()
                .fill(HoopColor.textTertiary)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 4 }
            Text(text)
                .font(HoopFont.subhead)
                .foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startScan() {
        attempt += 1
        scanning = true
        withAnimation { showHelp = false }
        if live.connected && !live.bonded { app.disconnect() }
        app.scan(model: model)
        let thisAttempt = attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            guard thisAttempt == attempt, !live.bonded else { return }
            scanning = false
            withAnimation(.spring) { showHelp = true }
        }
    }
}

private struct HoopPairStep: View {
    let model: WhoopModel
    @Binding var paired: Bool
    var body: some View {
        ScrollView {
            HoopPairPanel(model: model, paired: $paired)
                .hoopScreenPadding()
                .padding(.top, HoopSpace.xxl)
                .padding(.bottom, HoopSpace.l)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Soft rings travelling outward while searching (still, under Reduce Motion); a green core once found.
struct HoopRadar: View {
    let active: Bool
    let found: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var pulse = false

    private var animating: Bool { active && !motion.poseStill(reduceMotion) }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder((found ? HoopColor.recoveryHigh : HoopColor.text).opacity(0.22), lineWidth: 1)
                    .scaleEffect(animating ? (pulse ? 1.0 : 0.36) : 0.5 + 0.22 * Double(i))
                    .opacity(animating ? (pulse ? 0 : 1) : 0.85 - 0.28 * Double(i))
                    .animation(animating
                               ? .easeOut(duration: 2.7).repeatForever(autoreverses: false).delay(Double(i) * 0.9)
                               : .easeInOut(duration: 0.4),
                               value: pulse)
            }
            Circle()
                .fill(found ? HoopColor.recoveryHigh : HoopColor.surfaceHigh)
                .frame(width: 92, height: 92)
                .background {
                    HoopGlow(tint: found ? HoopColor.recoveryHigh : HoopColor.brandCyan, intensity: found ? 0.4 : 0.22)
                        .frame(width: 280, height: 280)
                }
            if found {
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(HoopColor.canvas)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HoopLogoMark(size: 46, style: .glyph, monochrome: true)
                    .transition(.opacity)
            }
        }
        .onAppear { if animating { pulse = true } }
        .onChange(of: animating) { _, a in
            pulse = false
            if a { DispatchQueue.main.async { pulse = true } }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: found)
        .accessibilityHidden(true)
    }
}

// MARK: - Profile

/// Date of birth, sex, height and weight. Shared by first run and the You tab.
struct HoopProfileForm: View {
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        HoopGroup {
            HoopRowContainer {
                HStack(spacing: HoopSpace.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Date of birth").font(HoopFont.body).foregroundStyle(HoopColor.text)
                        Text("\(profile.age) years").font(HoopFont.footnote).foregroundStyle(HoopColor.textSecondary)
                    }
                    Spacer(minLength: HoopSpace.s)
                    DatePicker("Date of birth", selection: $profile.dateOfBirth, in: ProfileStore.dateOfBirthRange,
                               displayedComponents: .date)
                        .labelsHidden()
                }
            }
            segmentedRow("Sex") {
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                    Text("Other").tag("nonbinary")
                }
            }
            stepperRow("Height", value: UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem)) {
                Stepper("Height", value: $profile.heightCm, in: 120...230, step: 1).labelsHidden()
            }
            stepperRow("Weight", value: UnitFormatter.massFromKilograms(profile.weightKg, system: unitSystem)) {
                Stepper("Weight", value: $profile.weightKg, in: 30...250, step: 0.5).labelsHidden()
            }
            segmentedRow("Units", last: true) {
                Picker("Units", selection: $unitSystemRaw) {
                    Text("Metric").tag(UnitSystem.metric.rawValue)
                    Text("Imperial").tag(UnitSystem.imperial.rawValue)
                }
            }
        }
    }

    private func segmentedRow<P: View>(_ title: LocalizedStringKey, last: Bool = false,
                                       @ViewBuilder picker: () -> P) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HoopSpace.s))
            : AnyLayout(HStackLayout(spacing: HoopSpace.m))
        let control = picker()
        return HoopRowContainer(last: last) {
            layout {
                Text(title).font(HoopFont.body).foregroundStyle(HoopColor.text)
                if !typeSize.isAccessibilitySize { Spacer(minLength: HoopSpace.s) }
                control
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 210)
            }
        }
    }

    private func stepperRow<S: View>(_ title: LocalizedStringKey, value: String,
                                     @ViewBuilder stepper: () -> S) -> some View {
        let control = stepper()
        return HoopRowContainer {
            HStack(spacing: HoopSpace.m) {
                Text(title).font(HoopFont.body).foregroundStyle(HoopColor.text)
                Spacer(minLength: HoopSpace.s)
                Text(value)
                    .font(HoopFont.value(.body))
                    .foregroundStyle(HoopColor.text)
                    .contentTransition(.numericText())
                control
            }
        }
    }
}

private struct HoopProfileStep: View {
    @EnvironmentObject private var profile: ProfileStore
    var body: some View {
        HoopStepScaffold(title: "About you",
                         subtitle: "Used for calories, heart-rate zones and your baselines. It stays on this iPhone.") {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HoopProfileForm()
                Label("Estimated max heart rate: \(profile.hrMax) bpm", systemImage: "heart")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct HoopDoneStep: View {
    let paired: Bool
    @State private var appear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HoopStepScaffold(title: paired ? "You're all set" : "Almost there",
                         subtitle: paired
                            ? "Hoop is reading your strap. Here's what happens next."
                            : "You can pair your strap any time from the You tab.") {
            VStack(alignment: .leading, spacing: 0) {
                row(HoopColor.heart, "Right now", "Live heart rate and today's strain start straight away.", last: false)
                row(HoopColor.sleep, "Tonight", "Wear your strap to bed. Hoop detects and stages your sleep.", last: false)
                row(HoopColor.recoveryHigh, "In about four nights", "Hoop has learned your baseline and your first recovery score appears.", last: true)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear || reduceMotion ? 0 : 10)
            .onAppear {
                if reduceMotion { appear = true; return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.9).delay(0.1)) { appear = true }
            }
        }
    }

    private func row(_ tint: Color, _ title: LocalizedStringKey, _ body: LocalizedStringKey, last: Bool) -> some View {
        HStack(alignment: .top, spacing: HoopSpace.l) {
            VStack(spacing: 0) {
                HoopRing(progress: 0.75, tint: tint, lineWidth: 3)
                    .frame(width: 16, height: 16)
                    .padding(.top, 3)
                if !last {
                    Rectangle()
                        .fill(HoopColor.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.text)
                Text(body)
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : HoopSpace.xxl)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pair a strap later

/// Pairing on its own (from the strap sheet or the You tab): choose, prepare, pair.
struct HoopPairingFlow: View {
    let onFinished: () -> Void

    private enum Step: Int { case choose, prepare, pair }
    @State private var step: Step = .choose
    @State private var paired = false
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HoopSpace.xxl) {
                    switch step {
                    case .choose:
                        Text("Which strap?")
                            .font(HoopFont.largeTitle)
                            .foregroundStyle(HoopColor.text)
                        HoopStrapChoiceStepContent(selection: $selectedModelRaw)
                    case .prepare:
                        Text("Free your strap")
                            .font(HoopFont.largeTitle)
                            .foregroundStyle(HoopColor.text)
                        HoopPrepareStepContent(model: selectedModel)
                    case .pair:
                        HoopPairPanel(model: selectedModel, paired: $paired)
                    }
                }
                .hoopScreenPadding()
                .padding(.vertical, HoopSpace.l)
            }
            .scrollIndicators(.hidden)
            .hoopBottomBar {
                if step != .pair || paired {
                    Button(action: next) { Text(nextTitle) }
                        .buttonStyle(HoopPrimaryButtonStyle(tint: step == .pair && paired ? HoopColor.recoveryHigh : HoopColor.text))
                        .hoopScreenPadding()
                        .padding(.top, HoopSpace.m)
                        .padding(.bottom, HoopSpace.s)
                }
            }
            .navigationTitle("Pair a strap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .choose ? "Cancel" : "Back") { back() }
                }
                if step == .pair && !paired {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { onFinished() }
                    }
                }
            }
        }
    }

    private var nextTitle: String {
        switch step {
        case .choose: return String(localized: "Continue")
        case .prepare: return String(localized: "My strap is ready")
        case .pair: return String(localized: "Done")
        }
    }

    private func next() {
        switch step {
        case .choose: withAnimation { step = .prepare }
        case .prepare: withAnimation { step = .pair }
        case .pair: onFinished()
        }
    }

    private func back() {
        switch step {
        case .choose: onFinished()
        case .prepare: withAnimation { step = .choose }
        case .pair: withAnimation { step = .prepare }
        }
    }
}

// MARK: - Logo

/// The Hoop mark, matching the app icon: an open ring, gap at the bottom, fading from green on the left
/// over cyan to violet on the right, around a solid core. `.tile` is the icon itself; `.glyph` is the
/// bare ring for use on the canvas, optionally monochrome. `drawn` animates the ring drawing itself in.
struct HoopLogoMark: View {
    enum Style { case tile, glyph }
    var size: CGFloat = 96
    var style: Style = .tile
    var monochrome = false
    var drawn = true

    var body: some View {
        let ring = style == .tile ? size * 0.60 : size * 0.84
        let line = ring * 0.143
        ZStack {
            if style == .tile {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.129, green: 0.145, blue: 0.184),
                                                  Color(red: 0.020, green: 0.024, blue: 0.031)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            Circle()
                .trim(from: 0.085, to: drawn ? 0.915 : 0.085)
                .stroke(monochrome
                        ? AnyShapeStyle(HoopColor.text)
                        : AnyShapeStyle(AngularGradient(colors: [HoopColor.brandGreen, HoopColor.brandCyan, HoopColor.brandViolet],
                                                        center: .center)),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: ring, height: ring)
                .shadow(color: monochrome ? .clear : HoopColor.brandCyan.opacity(0.45), radius: ring * 0.07)
            Circle()
                .fill(monochrome ? HoopColor.text : HoopColor.brandCore)
                .frame(width: ring * 0.207, height: ring * 0.207)
                .scaleEffect(drawn ? 1 : 0.4)
                .opacity(drawn ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
#endif
