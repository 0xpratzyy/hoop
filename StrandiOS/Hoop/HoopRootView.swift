#if os(iOS)
import SwiftUI

enum HoopTab: Hashable {
    case today, sleep, fuel, you
}

/// Hoop's shell: four tabs, with the first-run flow laid over them until it is finished.
struct HoopRootView: View {
    @AppStorage("hoop.onboarded") private var onboarded = false

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var homeScreenQuickActions: HomeScreenQuickActionSceneDelegate

    @State private var tab: HoopTab = HoopRootView.launchTab
    @State private var showDevices = false
    @State private var showLive = false

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                HoopTodayView(openTab: { t in withAnimation { tab = t } })
                    .tabItem { Label("Today", systemImage: "circle.circle.fill") }
                    .tag(HoopTab.today)
                HoopSleepView()
                    .tabItem { Label("Sleep", systemImage: "moon.fill") }
                    .tag(HoopTab.sleep)
                HoopFuelView()
                    .tabItem { Label("Fuel", systemImage: "flame.fill") }
                    .tag(HoopTab.fuel)
                HoopYouView()
                    .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                    .tag(HoopTab.you)
            }
            .tint(HoopColor.text)

            if !onboarded {
                HoopOnboardingView(onFinished: {
                    withAnimation(.easeInOut(duration: 0.4)) { onboarded = true }
                })
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(HoopBackground())
        .preferredColorScheme(.dark)
        .tint(HoopColor.accent)
        .task { await repo.refresh() }
        // Older screens (reached from You) can ask the shell for the device manager.
        .onChange(of: router.requestedDestination) { _, dest in
            guard let dest else { return }
            switch dest {
            case .devices: showDevices = true
            case .activeWorkout: showLive = true
            default: break
            }
            router.requestedDestination = nil
        }
        .onAppear { consumeQuickAction() }
        .onChange(of: homeScreenQuickActions.pendingAction) { _, _ in consumeQuickAction() }
        .sheet(isPresented: $showDevices) {
            NavigationStack {
                DevicesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDevices = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showLive) { HoopLiveHeartView() }
    }

    /// DEBUG screenshot aid: `--hoop-tab sleep|fuel|you` opens on that tab.
    private static var launchTab: HoopTab {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--hoop-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "sleep": return .sleep
            case "fuel": return .fuel
            case "you": return .you
            default: return .today
            }
        }
        #endif
        return .today
    }

    /// The Home Screen icon menu offers live heart rate; any older action is simply consumed.
    private func consumeQuickAction() {
        guard onboarded, let action = homeScreenQuickActions.pendingAction else { return }
        homeScreenQuickActions.consume(action)
        if action == .liveHeartRate { showLive = true }
    }
}
#endif
