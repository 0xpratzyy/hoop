#if os(iOS)
import MarkdownUI
import PhotosUI
import StrandDesign
import SwiftUI
import UIKit

// MARK: - Shared pieces

/// The small mark used wherever Hoop AI speaks: a sparkle in the brand gradient.
struct HoopAIGlyph: View {
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: [HoopColor.brandGreen, HoopColor.brandCyan, HoopColor.brandViolet],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            .accessibilityHidden(true)
    }
}

/// "Continue with ChatGPT", the sign-in button the plan-usage guidelines ask for.
struct HoopChatGPTButton: View {
    @ObservedObject private var ai = HoopAI.shared
    var onConnected: () -> Void = {}
    @State private var error: String?

    var body: some View {
        VStack(spacing: HoopSpace.s) {
            Button {
                Task {
                    do {
                        try await ai.connect()
                        onConnected()
                    } catch HoopChatGPTAuth.AuthError.cancelled {
                        // Closing the sheet isn't an error.
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: HoopSpace.s) {
                    if ai.auth.isSigningIn {
                        ProgressView().tint(HoopColor.canvas)
                    } else {
                        // OpenAI's own mark from the Sign in with ChatGPT button kit: the black logo on a
                        // white button ("Continue with ChatGPT", black logo), used as supplied.
                        Image("ChatGPTLogoBlack")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    Text("Continue with ChatGPT")
                }
            }
            .buttonStyle(HoopPrimaryButtonStyle())
            .disabled(ai.auth.isSigningIn)
            if let error {
                Text(error)
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.recoveryLow)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Opens ChatGPT's settings, where the person sets how much of their plan Hoop may use.
enum HoopAILinks {
    static let manageUsage = URL(string: "https://chatgpt.com/#settings")!
    static let help = URL(string: "https://help.openai.com/en/articles/20001542-using-your-chatgpt-plan-in-other-apps-and-sites")!
}

extension Theme {
    /// Chat replies in Hoop's type: body-sized text, quiet headings, comfortable paragraph spacing.
    static let hoop = Theme()
        .text {
            ForegroundColor(HoopColor.text)
            FontSize(16)
        }
        .strong { FontWeight(.semibold) }
        .emphasis { FontStyle(.italic) }
        .link { ForegroundColor(HoopColor.brandCyan) }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
        }
        .heading1 { c in c.label.markdownMargin(top: 12, bottom: 6).markdownTextStyle { FontWeight(.semibold); FontSize(17) } }
        .heading2 { c in c.label.markdownMargin(top: 12, bottom: 6).markdownTextStyle { FontWeight(.semibold); FontSize(17) } }
        .heading3 { c in c.label.markdownMargin(top: 10, bottom: 4).markdownTextStyle { FontWeight(.semibold); FontSize(16) } }
        .paragraph { c in c.label.relativeLineSpacing(.em(0.18)).markdownMargin(top: 0, bottom: 10) }
        .listItem { c in c.label.markdownMargin(top: .em(0.2)) }
}

// MARK: - Connect

/// What Hoop AI does, what it sends and where, then "Continue with ChatGPT".
struct HoopAIConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = HoopAI.shared
    @State private var showWelcome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HoopSpace.xl) {
                    HoopAIGlyph(size: 34)
                        .padding(.top, HoopSpace.s)
                    VStack(alignment: .leading, spacing: HoopSpace.s) {
                        Text("Hoop AI")
                            .font(HoopFont.largeTitle)
                            .foregroundStyle(HoopColor.text)
                        Text("A coach that reads your own numbers, powered by your ChatGPT plan.")
                            .font(HoopFont.body)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: HoopSpace.l) {
                        point("A daily briefing", "How hard to train today, from your recovery, sleep and strain.")
                        point("Ask Hoop", "Questions about your recovery, sleep or training, answered from your data.")
                        point("Sleep explained", "What helped or held back last night, and one thing to try tonight.")
                        point("Log food by photo", "Snap or describe a meal and get calories and protein.")
                    }
                    HoopSurface {
                        VStack(alignment: .leading, spacing: HoopSpace.s) {
                            Text("What's shared")
                                .font(HoopFont.headline)
                                .foregroundStyle(HoopColor.text)
                            Text("Only when you use an AI feature, Hoop sends OpenAI a short summary of the relevant numbers (recovery, strain, sleep, vitals, recent trends and anything you log or photograph) to write the answer. Nothing is sent in the background, and everything else stays on this iPhone.")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Uses your ChatGPT plan, with no API key. You can set how much Hoop may use in ChatGPT settings. Not medical advice.")
                                .font(HoopFont.subhead)
                                .foregroundStyle(HoopColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .hoopBottomBar {
                VStack(spacing: HoopSpace.s) {
                    if ai.isConnected {
                        Button("Done") { dismiss() }.buttonStyle(HoopPrimaryButtonStyle())
                    } else {
                        HoopChatGPTButton(onConnected: { showWelcome = true })
                    }
                    Link("How ChatGPT plan usage works", destination: HoopAILinks.help)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .hoopScreenPadding()
                .padding(.vertical, HoopSpace.m)
            }
            .background(HoopBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $showWelcome, onDismiss: { dismiss() }) { HoopAIWelcomeSheet() }
        }
        .presentationBackground(HoopColor.canvas)
    }

    private func point(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(HoopFont.headline).foregroundStyle(HoopColor.text)
            Text(body).font(HoopFont.subhead).foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Shown once, right after the first sign-in: "You're using your ChatGPT plan".
struct HoopAIWelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var ai = HoopAI.shared

    var body: some View {
        VStack(spacing: HoopSpace.xl) {
            Spacer(minLength: HoopSpace.l)
            HoopAIGlyph(size: 40)
            VStack(spacing: HoopSpace.s) {
                Text("You're using your ChatGPT plan")
                    .font(HoopFont.title)
                    .foregroundStyle(HoopColor.text)
                    .multilineTextAlignment(.center)
                Text("Eligible usage in Hoop uses your ChatGPT plan. Manage usage in your ChatGPT settings.")
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let email = ai.auth.account?.email {
                    Text(email)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textTertiary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: HoopSpace.l)
            VStack(spacing: HoopSpace.m) {
                Button("Done") {
                    ai.welcomed = true
                    dismiss()
                }
                .buttonStyle(HoopPrimaryButtonStyle())
                Button("Manage usage") { openURL(HoopAILinks.manageUsage) }
                    .buttonStyle(HoopSecondaryButtonStyle())
            }
        }
        .hoopScreenPadding()
        .padding(.vertical, HoopSpace.xl)
        .presentationDetents([.medium])
        .presentationBackground(HoopColor.canvas)
        .onDisappear { ai.welcomed = true }
    }
}

// MARK: - Ask Hoop

/// Where Ask Hoop opens from; it picks the starter questions.
enum HoopAskTopic {
    case today, sleep, fuel

    var suggestions: [String] {
        switch self {
        case .today:
            return [String(localized: "Should I train hard today?"),
                    String(localized: "Why is my recovery where it is?"),
                    String(localized: "How has my week looked?")]
        case .sleep:
            return [String(localized: "How can I get more deep sleep?"),
                    String(localized: "What time should I go to bed tonight?"),
                    String(localized: "How consistent has my sleep been?")]
        case .fuel:
            return [String(localized: "What should I eat for the rest of today?"),
                    String(localized: "Am I on track for my goal?"),
                    String(localized: "How do I hit my protein target?")]
        }
    }
}

/// The toolbar sparkle that opens Ask Hoop, or the connect sheet when AI is off.
struct HoopAskButton: View {
    let topic: HoopAskTopic
    @ObservedObject private var ai = HoopAI.shared
    @State private var showAsk = false
    @State private var showConnect = false

    var body: some View {
        Button {
            if ai.isConnected { showAsk = true } else { showConnect = true }
        } label: {
            HoopAIGlyph(size: 16)
        }
        .accessibilityLabel("Ask Hoop")
        .sheet(isPresented: $showAsk) { HoopAskView(topic: topic) }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
    }
}

/// Ask Hoop: a chat grounded in the person's data.
struct HoopAskView: View {
    let topic: HoopAskTopic
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = HoopAI.shared
    @State private var draft = ""
    @State private var context = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HoopSpace.l) {
                        if ai.messages.isEmpty { intro }
                        ForEach(ai.messages) { m in
                            bubble(m).id(m.id)
                        }
                        if let error = ai.lastError {
                            errorView(error)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .hoopScreenPadding()
                    .padding(.top, HoopSpace.s)
                    .padding(.bottom, HoopSpace.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: ai.messages) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .hoopBottomBar { composer }
            .background(HoopBackground())
            .navigationTitle("Ask Hoop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !ai.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { ai.clearConversation() } label: { Image(systemName: "square.and.pencil") }
                            .accessibilityLabel("New conversation")
                            .disabled(ai.isAnswering)
                    }
                }
            }
        }
        .presentationBackground(HoopColor.canvas)
        .task { context = await buildContext() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: HoopSpace.l) {
            HoopAIGlyph(size: 28).padding(.top, HoopSpace.l)
            Text("Ask about your recovery, sleep, strain or food. Hoop answers from your own numbers.")
                .font(HoopFont.title3)
                .foregroundStyle(HoopColor.text)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: HoopSpace.s) {
                ForEach(topic.suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s)
                            .font(HoopFont.callout)
                            .foregroundStyle(HoopColor.text)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, HoopSpace.l)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(HoopColor.surface))
                    }
                    .buttonStyle(HoopPressStyle())
                }
            }
        }
        .padding(.bottom, HoopSpace.l)
    }

    @ViewBuilder
    private func bubble(_ m: HoopAI.Message) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(m.text)
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(HoopColor.surfaceHigh))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if m.text.isEmpty {
                    HoopThinking()
                } else {
                    Markdown(m.text)
                        .markdownTheme(.hoop)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: HoopSpace.s) {
            Text(error)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.recoveryLow)
                .fixedSize(horizontal: false, vertical: true)
            if error.contains("ChatGPT settings") {
                Link("Manage usage", destination: HoopAILinks.manageUsage)
                    .font(HoopFont.footnote.weight(.semibold))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: HoopSpace.s) {
                TextField("Ask Hoop", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(HoopColor.surface))
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                Button {
                    if ai.isAnswering { ai.stopAnswering() } else { send(draft) }
                } label: {
                    Image(systemName: ai.isAnswering ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HoopColor.canvas)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(HoopColor.text))
                }
                .disabled(!ai.isAnswering && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!ai.isAnswering && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .accessibilityLabel(ai.isAnswering ? "Stop" : "Send")
            }
            Text("Using your ChatGPT plan · \(ai.modelDisplayName)")
                .font(HoopFont.caption2)
                .foregroundStyle(HoopColor.textTertiary)
        }
        .hoopScreenPadding()
        .padding(.vertical, HoopSpace.s)
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        Task {
            if context.isEmpty { context = await buildContext() }
            ai.ask(t, context: context)
        }
    }

    private func buildContext() async -> String {
        let snap = await HoopTodayLoader.load(repo: repo, profile: profile)
        return HoopAIContext.build(repo: repo, profile: profile, snapshot: snap)
    }
}

/// Three dots that breathe while Hoop AI is thinking. Still under Reduce Motion, Low Power Mode and the
/// app's own "Reduce motion" setting (`NoopMotionState`).
struct HoopThinking: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var on = false

    private var still: Bool { motion.poseStill(reduceMotion) }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(HoopColor.textSecondary)
                    .frame(width: 7, height: 7)
                    .opacity(still ? 0.6 : (on ? 1 : 0.25))
                    .animation(still ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .padding(.vertical, 6)
        .onAppear { on = true }
        .accessibilityLabel("Hoop is thinking")
    }
}

// MARK: - Today briefing

/// The briefing under the recovery hoop: two or three sentences for today, or a quiet invitation when
/// Hoop AI is off.
struct HoopAIBriefing: View {
    let snapshot: HoopTodaySnapshot
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var ai = HoopAI.shared
    @State private var showConnect = false
    @State private var showAsk = false

    var body: some View {
        Group {
            if ai.isConnected {
                connected
            } else if !ai.promptDismissed {
                invitation
            }
        }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
        .sheet(isPresented: $showAsk) { HoopAskView(topic: .today) }
    }

    private var todayKey: String { Repository.localDayKey(Date()) }

    private var connected: some View {
        let text = ai.isBriefing ? ai.briefingStreaming : (ai.briefing?.day == todayKey ? ai.briefing?.text : nil)
        return HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HStack(spacing: 6) {
                    HoopAIGlyph(size: 13)
                    Text("Today's briefing")
                        .font(HoopFont.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textSecondary)
                    Spacer()
                    if !ai.isBriefing, text != nil {
                        Button {
                            Task { await ai.generateBriefing(context: context(), force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(HoopColor.textTertiary)
                                .frame(minWidth: 32, minHeight: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rewrite briefing")
                    }
                }
                if let text, !text.isEmpty {
                    Text(text)
                        .font(HoopFont.body)
                        .foregroundStyle(HoopColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeOut(duration: 0.15), value: text)
                } else if ai.isBriefing {
                    HoopThinking()
                } else if let error = ai.briefingError {
                    Text(error)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await ai.generateBriefing(context: context(), force: true) } }
                        .font(HoopFont.footnote.weight(.semibold))
                } else {
                    Button { Task { await ai.generateBriefing(context: context()) } } label: {
                        Text("Write today's briefing")
                    }
                    .buttonStyle(HoopSecondaryButtonStyle())
                }
                Button { showAsk = true } label: {
                    HStack {
                        Text("Ask Hoop")
                            .font(HoopFont.callout.weight(.semibold))
                            .foregroundStyle(HoopColor.text)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(HoopColor.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(HoopPressStyle())
                .padding(.top, 2)
            }
        }
        .task(id: snapshot.loaded) {
            // One briefing a day, written the first time Today opens with data loaded.
            guard snapshot.loaded, snapshot.hasAnyData, ai.briefing?.day != todayKey else { return }
            await ai.generateBriefing(context: context())
        }
    }

    private var invitation: some View {
        HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HStack(spacing: 6) {
                    HoopAIGlyph(size: 13)
                    Text("Hoop AI")
                        .font(HoopFont.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textSecondary)
                }
                Text("Get a daily briefing and ask questions about your data, using your ChatGPT plan.")
                    .font(HoopFont.callout)
                    .foregroundStyle(HoopColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: HoopSpace.m) {
                    Button("Set up") { showConnect = true }
                        .buttonStyle(HoopSecondaryButtonStyle())
                    Button("Not now") { withAnimation { ai.promptDismissed = true } }
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func context() -> String {
        HoopAIContext.build(repo: repo, profile: profile, snapshot: snapshot)
    }
}

// MARK: - Sleep insight

/// "Explain my night" under the sleep hoop.
struct HoopAISleepInsight: View {
    let nightKey: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var ai = HoopAI.shared
    @State private var showConnect = false

    var body: some View {
        let text = ai.sleepStreaming[nightKey] ?? ai.sleepInsights[nightKey]
        HoopSurface {
            VStack(alignment: .leading, spacing: HoopSpace.m) {
                HStack(spacing: 6) {
                    HoopAIGlyph(size: 13)
                    Text("Your night, explained")
                        .font(HoopFont.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textSecondary)
                }
                if let text, !text.isEmpty {
                    Text(text)
                        .font(HoopFont.body)
                        .foregroundStyle(HoopColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else if ai.sleepStreaming[nightKey] != nil {
                    HoopThinking()
                } else {
                    Button(ai.isConnected ? "Explain my night" : "Explain my night with Hoop AI") {
                        if ai.isConnected {
                            Task { await explain() }
                        } else {
                            showConnect = true
                        }
                    }
                    .buttonStyle(HoopSecondaryButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
    }

    private func explain() async {
        let snap = await HoopTodayLoader.load(repo: repo, profile: profile)
        await ai.explainNight(key: nightKey, context: HoopAIContext.build(repo: repo, profile: profile, snapshot: snap))
    }
}

// MARK: - Food

/// The AI half of "Log food": describe a meal or take a photo, and the estimate fills the form.
struct HoopAIFoodAssist: View {
    /// Receives the estimate so the form can be filled in for the person to check.
    let onEstimate: (HoopAI.FoodEstimate) -> Void
    @ObservedObject private var ai = HoopAI.shared
    @State private var description = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showConnect = false
    @State private var working = false
    @State private var note: String?
    @State private var error: String?

    var body: some View {
        Section {
            if ai.isConnected {
                TextField("Describe it, e.g. two eggs and toast", text: $description, axis: .vertical)
                    .lineLimit(1...3)
                if let photo {
                    HStack(spacing: HoopSpace.m) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Photo added")
                            .foregroundStyle(HoopColor.textSecondary)
                        Spacer()
                        Button { self.photo = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(HoopColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove photo")
                    }
                }
                HStack(spacing: HoopSpace.l) {
                    Menu {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                        }
                    } label: {
                        Label("Photo", systemImage: "camera")
                    }
                    Spacer()
                    Button {
                        Task { await estimate() }
                    } label: {
                        if working {
                            ProgressView()
                        } else {
                            Label("Estimate", systemImage: "sparkle")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(working || (description.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil))
                }
                .buttonStyle(.borderless)
            } else {
                Button { showConnect = true } label: {
                    Label("Log with a photo or description", systemImage: "sparkle")
                }
            }
        } header: {
            Text("Hoop AI")
        } footer: {
            if let error {
                Text(error).foregroundStyle(HoopColor.recoveryLow)
            } else if let note {
                Text(note)
            } else if ai.isConnected {
                Text("Uses your ChatGPT plan. Check the numbers before adding.")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            HoopCameraPicker { image in photo = image }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
    }

    private func estimate() async {
        working = true
        error = nil
        note = nil
        defer { working = false }
        do {
            let e = try await ai.estimateFood(description: description, photo: photo)
            note = e.note
            onEstimate(e)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The system camera, for photographing a meal.
struct HoopCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: HoopCameraPicker
        init(_ parent: HoopCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - You

/// The Hoop AI rows in You: connect, or the account, model, usage and disconnect.
struct HoopAISettingsGroup: View {
    @ObservedObject private var ai = HoopAI.shared
    @Environment(\.openURL) private var openURL
    @State private var showConnect = false
    @State private var confirmDisconnect = false

    var body: some View {
        HoopGroupLabel("Hoop AI")
        HoopGroup {
            if ai.isConnected {
                HoopRow(title: "ChatGPT", subtitle: accountLine, value: ai.auth.account?.plan)
                Menu {
                    ForEach(ai.models) { m in
                        Button {
                            ai.modelSlug = m.slug
                        } label: {
                            if m.slug == ai.model { Label(m.displayName, systemImage: "checkmark") } else { Text(m.displayName) }
                        }
                    }
                } label: {
                    HoopRow(title: "Model", value: ai.modelDisplayName, chevron: true)
                }
                .buttonStyle(HoopRowButtonStyle())
                Button { openURL(HoopAILinks.manageUsage) } label: {
                    HoopRow(title: "Manage usage", subtitle: String(localized: "Set how much of your plan Hoop may use"), external: true)
                }
                .buttonStyle(HoopRowButtonStyle())
                Button { confirmDisconnect = true } label: {
                    HoopRow(title: "Disconnect ChatGPT", titleColor: HoopColor.recoveryLow, last: true)
                }
                .buttonStyle(HoopRowButtonStyle())
            } else {
                Button { showConnect = true } label: {
                    HoopRow(title: "Set up Hoop AI",
                            subtitle: String(localized: "Daily briefing, Ask Hoop and food photos, with your ChatGPT plan"),
                            chevron: true, last: true)
                }
                .buttonStyle(HoopRowButtonStyle())
            }
        }
        .task { if ai.isConnected && ai.models.isEmpty { await ai.loadModels() } }
        .sheet(isPresented: $showConnect) { HoopAIConnectSheet() }
        .confirmationDialog("Disconnect ChatGPT?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await ai.disconnect() } }
        } message: {
            Text("Hoop AI turns off. Your briefings and chat history stay on this iPhone.")
        }
    }

    private var accountLine: String? {
        let a = ai.auth.account
        return a?.email ?? a?.name
    }
}
#endif
