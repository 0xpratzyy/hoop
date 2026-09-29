#if os(iOS)
import SwiftUI

/// You: the strap, your details and preferences, connections, and everything else one quiet row away.
struct HoopYouView: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var showStrap = false
    @State private var showPairing = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Button { showStrap = true } label: { HoopStrapHero(style: .row) }
                        .buttonStyle(HoopPressStyle())
                        .accessibilityHint("Opens your strap")
                        .padding(.top, HoopSpace.s)
                    HStack(spacing: HoopSpace.m) {
                        if live.connected {
                            Button { ble.syncNow() } label: {
                                Text(live.backfilling ? "Syncing…" : "Sync now")
                            }
                            .buttonStyle(HoopSecondaryButtonStyle())
                            .disabled(live.backfilling)
                        }
                        Button { showPairing = true } label: {
                            Text(live.connected ? "New strap" : "Pair a strap")
                        }
                        .buttonStyle(HoopSecondaryButtonStyle())
                    }
                    .padding(.top, HoopSpace.m)

                    HoopGroupLabel("Profile")
                    HoopGroup {
                        Button { showProfile = true } label: {
                            HoopRow(title: "Your details", value: profileSummary, chevron: true, last: true)
                        }
                        .buttonStyle(HoopRowButtonStyle())
                    }

                    HoopGroupLabel("Preferences")
                    HoopGroup {
                        pickerRow("Strain scale") {
                            Picker("Strain scale", selection: $effortScaleRaw) {
                                Text("0–21").tag(EffortScale.whoop.rawValue)
                                Text("0–100").tag(EffortScale.hundred.rawValue)
                            }
                        }
                        pickerRow("Units", last: true) {
                            Picker("Units", selection: $unitSystemRaw) {
                                Text("Metric").tag(UnitSystem.metric.rawValue)
                                Text("Imperial").tag(UnitSystem.imperial.rawValue)
                            }
                        }
                    }

                    HoopAISettingsGroup()

                    HoopGroupLabel("Connections")
                    HoopGroup {
                        link(.appleHealth, title: "Apple Health", value: String(localized: "Read and write"))
                        link(.alarm, title: "Smart alarm", value: String(localized: "Wake with a buzz"), last: true)
                    }

                    HoopGroupLabel("More")
                    HoopGroup {
                        link(.advanced, title: "Advanced", subtitle: String(localized: "Import, backup, troubleshooting"))
                        link(.about, title: "About Hoop", value: HoopAppInfo.versionString, last: true)
                    }
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .hoopTabRoot("You")
            .navigationDestination(for: HoopYouRoute.self) { route in
                route.destination
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabRouteDestinations()
        }
        .sheet(isPresented: $showStrap) { HoopStrapSheet() }
        .sheet(isPresented: $showPairing) { HoopPairingFlow(onFinished: { showPairing = false }) }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                ScrollView {
                    HoopProfileForm()
                        .hoopScreenPadding()
                        .padding(.top, HoopSpace.s)
                        .padding(.bottom, HoopSpace.xxl)
                }
                .navigationTitle("Your details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showProfile = false }.fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var profileSummary: String {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return "\(profile.age) · \(UnitFormatter.massFromKilograms(profile.weightKg, system: system))"
    }

    private func pickerRow<P: View>(_ title: LocalizedStringKey, last: Bool = false,
                                    @ViewBuilder picker: () -> P) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HoopSpace.s))
            : AnyLayout(HStackLayout(spacing: HoopSpace.m))
        let control = picker()
        return HoopRowContainer(last: last) {
            layout {
                Text(title)
                    .font(HoopFont.body)
                    .foregroundStyle(HoopColor.text)
                if !typeSize.isAccessibilitySize { Spacer(minLength: HoopSpace.s) }
                control
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 176)
            }
        }
    }

    private func link(_ route: HoopYouRoute, title: LocalizedStringKey, subtitle: String? = nil,
                      value: String? = nil, last: Bool = false) -> some View {
        NavigationLink(value: route) {
            HoopRow(title: title, subtitle: subtitle, value: value, chevron: true, last: last)
        }
        .buttonStyle(HoopRowButtonStyle())
    }
}

enum HoopYouRoute: Hashable {
    case appleHealth, alarm, advanced, dataSources, backup, diagnostics, settings, about

    @ViewBuilder var destination: some View {
        switch self {
        case .appleHealth: AppleHealthView()
        case .alarm: SmartAlarmView()
        case .advanced: HoopAdvancedView()
        case .dataSources: DataSourcesView()
        case .backup: BackupSyncView()
        case .diagnostics: TestCentreView()
        case .settings: SettingsView()
        case .about: HoopAboutView()
        }
    }
}

enum HoopAppInfo {
    static var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// The rarely needed tools, gathered in one place: importing history, backups, diagnostics and the full
/// NOOP settings.
struct HoopAdvancedView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HoopGroup {
                    row(.dataSources, "Import history", subtitle: String(localized: "WHOOP export, Apple Health"))
                    row(.backup, "Backup & restore")
                    row(.diagnostics, "Troubleshooting", subtitle: String(localized: "Logs and diagnostics"))
                    row(.settings, "Advanced settings", last: true)
                }
                Text("These screens come from NOOP, the open-source engine Hoop is built on, so they look a little different.")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, HoopSpace.m)
            }
            .hoopScreenPadding()
            .padding(.top, HoopSpace.s)
            .padding(.bottom, HoopSpace.xxl)
        }
        .scrollIndicators(.hidden)
        .background(HoopBackground())
        .navigationTitle("Advanced")
    }

    private func row(_ route: HoopYouRoute, _ title: LocalizedStringKey, subtitle: String? = nil,
                     last: Bool = false) -> some View {
        NavigationLink(value: route) {
            HoopRow(title: title, subtitle: subtitle, chevron: true, last: last)
        }
        .buttonStyle(HoopRowButtonStyle())
    }
}

/// About: what Hoop is, the people whose work it stands on, the licence, and the fine print.
struct HoopAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: HoopSpace.l) {
                    HoopLogoMark(size: 84)
                    VStack(spacing: 2) {
                        Text("Hoop")
                            .font(HoopFont.title)
                            .foregroundStyle(HoopColor.text)
                        Text("Version \(HoopAppInfo.versionString)")
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                    Text("A free companion for WHOOP straps. Hoop pairs over Bluetooth, keeps your data on this iPhone, and computes recovery, strain, heart rate variability and sleep itself. Optional Hoop AI uses your ChatGPT plan and sends a summary to OpenAI only when you use it.")
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, HoopSpace.xs)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, HoopSpace.l)

                HoopGroupLabel("Built on")
                HoopGroup {
                    credit("NOOP", "The open-source, local-first WHOOP app whose Bluetooth, storage and analytics power Hoop.",
                           "https://github.com/ryanbr/noop")
                    credit("Zhoop", "The weight-loss fork of NOOP that Hoop's Fuel tab comes from.",
                           "https://github.com/hackyguru/zhoop")
                    credit("my-whoop", "WHOOP 4.0 protocol research.", "https://github.com/johnmiddleton12/my-whoop")
                    credit("goose", "WHOOP 5.0 / MG protocol research.", "https://github.com/b-nnett/goose")
                    credit("GRDB, MarkdownUI, ZIPFoundation", "Open-source libraries under their own licences.", nil,
                           last: true)
                }

                HoopGroupLabel("Licence")
                HoopSurface {
                    VStack(alignment: .leading, spacing: HoopSpace.m) {
                        Text("Hoop is a fork of NOOP and is distributed under the PolyForm Noncommercial License 1.0.0. It is free, and may only be used for noncommercial purposes.")
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Required Notice: Copyright 2026 NoopApp")
                            .font(HoopFont.subhead.weight(.semibold))
                            .foregroundStyle(HoopColor.text)
                        Link(destination: URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!) {
                            (Text("polyformproject.org/licenses/noncommercial/1.0.0")
                                .underline(color: HoopColor.textTertiary)
                             + Text("  ")
                             + Text(Image(systemName: "arrow.up.right"))
                                .foregroundStyle(HoopColor.textTertiary))
                                .font(HoopFont.footnote)
                                .foregroundStyle(HoopColor.text)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                HoopGroupLabel("Fine print")
                VStack(alignment: .leading, spacing: HoopSpace.m) {
                    Text("Hoop is not affiliated with, endorsed by, or connected to WHOOP, Inc. \"WHOOP\" is used only to identify the hardware Hoop works with. Hoop contains no WHOOP software or assets.")
                    Text("Hoop is not a medical device. Its numbers are estimates for general wellness and must not be used for diagnosis or treatment.")
                }
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
            .hoopScreenPadding()
            .padding(.bottom, HoopSpace.section)
        }
        .scrollIndicators(.hidden)
        .background(HoopBackground())
        .navigationTitle("About")
    }

    @ViewBuilder
    private func credit(_ name: String, _ body: String, _ url: String?, last: Bool = false) -> some View {
        let content = HoopRowContainer(last: last) {
            HStack(alignment: .firstTextBaseline, spacing: HoopSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(HoopFont.headline)
                        .foregroundStyle(HoopColor.text)
                    Text(body)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: HoopSpace.s)
                if url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        if let url, let u = URL(string: url) {
            Link(destination: u) { content }
                .buttonStyle(HoopRowButtonStyle())
                .accessibilityHint("Opens \(u.host ?? "the project") in Safari")
        } else {
            content
        }
    }
}
#endif
