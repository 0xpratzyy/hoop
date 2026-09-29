#if os(iOS)
import SwiftUI
import WhoopProtocol

// MARK: - Live heart rate

/// Full-screen live heart rate: the number, a beating heart, the current zone and the last few minutes.
/// Arms the strap's realtime stream while open and releases it on close.
struct HoopLiveHeartView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var armed = false

    private var bpm: Int? {
        guard live.connected else { return nil }
        if let b = model.bpm, b > 0 { return b }
        if let h = live.heartRate, h > 0 { return h }
        return nil
    }

    private var zone: HoopZone? { bpm.map { HoopZone.of(bpm: $0, hrMax: profile.hrMax) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live heart rate")
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.text)
                Spacer()
                HoopIconButton(systemName: "xmark", label: "Close") { dismiss() }
            }
            .padding(.top, HoopSpace.s)
            Spacer(minLength: HoopSpace.xl)
            center
            Spacer(minLength: HoopSpace.xl)
            if live.connected {
                VStack(spacing: HoopSpace.xxl) {
                    zoneScale
                    trace
                    Button { model.buzzStrapOnce() } label: {
                        Label("Buzz my strap", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .buttonStyle(HoopSecondaryButtonStyle())
                }
                .transition(.opacity)
            }
        }
        .hoopScreenPadding()
        .padding(.bottom, HoopSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The glow is a background so its size never enters layout.
        .background {
            ZStack {
                HoopBackground()
                HoopGlow(tint: zone?.color ?? HoopColor.heart, intensity: bpm == nil ? 0.12 : 0.24)
                    .frame(width: 620, height: 620)
                    .offset(y: -150)
                    .animation(.easeInOut(duration: 0.8), value: zone)
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.3), value: live.connected)
        .onAppear {
            guard !armed else { return }
            armed = true
            model.startRealtimeHR()
            model.getBattery()
        }
        .onDisappear {
            if armed { model.stopRealtimeHR(); armed = false }
        }
        .presentationBackground(HoopColor.canvas)
    }

    @ViewBuilder
    private var center: some View {
        if let bpm {
            VStack(spacing: 6) {
                HoopHeartGlyph(bpm: bpm, size: 26, color: zone?.color ?? HoopColor.heart)
                Text("\(bpm)")
                    .font(HoopFont.number(124))
                    .foregroundStyle(HoopColor.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: bpm)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("beats per minute")
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
                if let zone {
                    Text(zone.label)
                        .font(HoopFont.subhead.weight(.semibold))
                        .foregroundStyle(zone.color)
                        .padding(.top, HoopSpace.s)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(bpm) beats per minute. \(zone?.label ?? "")"))
        } else if !live.connected {
            VStack(spacing: HoopSpace.l) {
                HoopHeartGlyph(bpm: nil, size: 40)
                VStack(spacing: 6) {
                    Text("Your strap isn't connected.")
                        .font(HoopFont.title3)
                        .foregroundStyle(HoopColor.text)
                    Text("Connect it to watch your heart rate live.")
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .multilineTextAlignment(.center)
                Button("Connect strap") { model.scan(model: WhoopModel.persisted) }
                    .buttonStyle(HoopPrimaryButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, HoopSpace.s)
            }
        } else {
            VStack(spacing: HoopSpace.l) {
                HoopHeartGlyph(bpm: nil, size: 40)
                Text("Waiting for the first beat…")
                    .font(HoopFont.callout)
                    .foregroundStyle(HoopColor.textSecondary)
            }
        }
    }

    /// The five zones as a segmented bar with a marker at the current rate.
    private var zoneScale: some View {
        let zones = HoopZone.allCases
        return VStack(spacing: HoopSpace.s) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(zones, id: \.self) { z in
                            Capsule().fill(z.color.opacity(zone == z ? 1 : 0.24))
                        }
                    }
                    .frame(height: 6)
                    if let bpm {
                        let f = HoopZone.fraction(bpm: bpm, hrMax: profile.hrMax)
                        Circle()
                            .fill(HoopColor.text)
                            .overlay(Circle().strokeBorder(HoopColor.canvas, lineWidth: 2.5))
                            .frame(width: 16, height: 16)
                            .offset(x: min(max(w * f - 8, 0), w - 16))
                            .animation(.snappy, value: bpm)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text("Rest")
                Spacer()
                Text("Max \(profile.hrMax)")
            }
            .font(HoopFont.caption)
            .foregroundStyle(HoopColor.textTertiary)
        }
        .accessibilityHidden(true)
    }

    /// The last ten minutes of heart rate.
    private var trace: some View {
        let cutoff = Int(Date().timeIntervalSince1970) - 600
        let values = live.recentHrSamples.filter { $0.ts >= cutoff && $0.bpm > 25 }.map { Optional(Double($0.bpm)) }
        return VStack(alignment: .leading, spacing: HoopSpace.s) {
            Text("Last 10 minutes")
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
            if values.count >= 2 {
                HoopSparkline(values: values, tint: zone?.color ?? HoopColor.heart, lineWidth: 2, fill: true)
                    .frame(height: 72)
            } else {
                Text("The trace fills in as your strap streams.")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Heart-rate zones as a share of max heart rate.
enum HoopZone: Int, CaseIterable, Hashable {
    case rest, easy, aerobic, threshold, peak

    var label: String {
        switch self {
        case .rest: return String(localized: "Zone 1 · Recovery")
        case .easy: return String(localized: "Zone 2 · Easy")
        case .aerobic: return String(localized: "Zone 3 · Aerobic")
        case .threshold: return String(localized: "Zone 4 · Threshold")
        case .peak: return String(localized: "Zone 5 · Peak")
        }
    }

    var color: Color {
        switch self {
        case .rest: return Color(red: 0.62, green: 0.66, blue: 0.74)
        case .easy: return HoopColor.strain
        case .aerobic: return HoopColor.recoveryHigh
        case .threshold: return HoopColor.recoveryMid
        case .peak: return HoopColor.heart
        }
    }

    static func fraction(bpm: Int, hrMax: Int) -> Double {
        // Map 40% … 100% of max onto the bar.
        let pct = Double(bpm) / Double(max(hrMax, 100))
        return min(max((pct - 0.4) / 0.6, 0), 1)
    }

    static func of(bpm: Int, hrMax: Int) -> HoopZone {
        let pct = Double(bpm) / Double(max(hrMax, 100))
        switch pct {
        case ..<0.6: return .rest
        case ..<0.7: return .easy
        case ..<0.8: return .aerobic
        case ..<0.9: return .threshold
        default: return .peak
        }
    }
}

// MARK: - Strap sheet

/// The strap at a glance, with the everyday controls: sync, buzz, reconnect and pairing.
struct HoopStrapSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    @State private var showPairing = false
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HoopStrapHero()
                        .padding(.top, HoopSpace.s)

                    Group {
                        if live.connected {
                            Button { ble.syncNow() } label: {
                                Text(live.backfilling ? "Syncing…" : "Sync now")
                            }
                            .buttonStyle(HoopPrimaryButtonStyle())
                            .disabled(live.backfilling)
                        } else {
                            Button { model.scan(model: WhoopModel(rawValue: selectedModelRaw) ?? .whoop4) } label: {
                                Text("Reconnect")
                            }
                            .buttonStyle(HoopPrimaryButtonStyle())
                        }
                    }
                    .padding(.top, HoopSpace.xxl)

                    if let hint = live.pairingHint ?? live.reconnectGuide {
                        Label(hint, systemImage: "info.circle")
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, HoopSpace.l)
                            .padding(.horizontal, 4)
                    }

                    HoopGroup {
                        HoopRow(title: "Last sync", value: live.lastSyncedAt.map {
                            HoopFormat.relative(Date(timeIntervalSince1970: $0))
                        } ?? String(localized: "Not yet"),
                                last: live.strapFirmware == nil && live.advertisingName == nil)
                        if let fw = live.strapFirmware {
                            HoopRow(title: "Firmware", value: fw, last: live.advertisingName == nil)
                        }
                        if let name = live.advertisingName {
                            HoopRow(title: "Name", value: name, last: true)
                        }
                    }
                    .padding(.top, HoopSpace.xxl)

                    HoopGroup {
                        if live.connected {
                            Button { model.buzzStrapOnce() } label: { HoopRow(title: "Buzz strap") }
                                .buttonStyle(HoopRowButtonStyle())
                        }
                        Button { showPairing = true } label: { HoopRow(title: "Pair a strap", chevron: true) }
                            .buttonStyle(HoopRowButtonStyle())
                        Button { showAdvanced = true } label: {
                            HoopRow(title: "Advanced device settings", chevron: true, last: true)
                        }
                        .buttonStyle(HoopRowButtonStyle())
                    }
                    .padding(.top, HoopSpace.l)

                    if live.connected {
                        HoopGroup {
                            Button(role: .destructive) { model.disconnect() } label: {
                                HoopRow(title: "Disconnect", titleColor: HoopColor.recoveryLow, last: true)
                            }
                            .buttonStyle(HoopRowButtonStyle())
                        }
                        .padding(.top, HoopSpace.l)
                    }
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Your strap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPairing) { HoopPairingFlow(onFinished: { showPairing = false }) }
            .sheet(isPresented: $showAdvanced) {
                NavigationStack {
                    DevicesView()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showAdvanced = false }
                            }
                        }
                }
            }
        }
    }
}

/// The strap's battery hoop with its name and connection state. `.hero` is the centred sheet header;
/// `.row` is the compact card on the You tab.
struct HoopStrapHero: View {
    enum Style { case hero, row }
    var style: Style = .hero

    @EnvironmentObject private var live: LiveState
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue

    /// The strap's own last reported charge (never cleared on disconnect; see `LiveState.batteryPct`).
    private var pct: Double? { live.activeIsWhoop ? live.batteryPct : nil }
    private var tint: Color {
        live.connected ? HoopColor.battery(pct, charging: live.charging == true) : HoopColor.textTertiary
    }

    var body: some View {
        switch style {
        case .hero: hero
        case .row: row
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                HoopRing(progress: (pct ?? 0) / 100, tint: tint, lineWidth: 10)
                VStack(spacing: 0) {
                    if live.charging == true && live.connected {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HoopColor.recoveryHigh)
                    }
                    if let pct {
                        HoopHeroNumber(value: "\(Int(pct.rounded()))", symbol: "%", size: 36)
                    } else {
                        Text(HoopFormat.dash)
                            .font(HoopFont.number(32))
                            .foregroundStyle(HoopColor.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 128, height: 128)
            .background {
                if live.connected, pct != nil { HoopGlow(tint: tint, intensity: 0.2).frame(width: 300, height: 300) }
            }
            Text(selectedModelRaw)
                .font(HoopFont.title3)
                .foregroundStyle(HoopColor.text)
                .padding(.top, HoopSpace.xl)
            HStack(spacing: 4) {
                HoopLiveDot(tint: HoopColor.recoveryHigh, active: live.connected)
                Text(statusText)
                    .font(HoopFont.subhead)
                    .foregroundStyle(HoopColor.textSecondary)
            }
            .padding(.top, 4)
            if !live.connected, pct != nil {
                Text("Battery as last reported")
                    .font(HoopFont.caption)
                    .foregroundStyle(HoopColor.textTertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var row: some View {
        HStack(spacing: HoopSpace.l) {
            ZStack {
                HoopRing(progress: (pct ?? 0) / 100, tint: tint, lineWidth: 5)
                if live.charging == true && live.connected {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HoopColor.recoveryHigh)
                } else {
                    Text(pct.map { "\(Int($0.rounded()))" } ?? HoopFormat.dash)
                        .font(HoopFont.number(15))
                        .foregroundStyle(pct == nil ? HoopColor.textTertiary : HoopColor.text)
                }
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedModelRaw)
                    .font(HoopFont.headline)
                    .foregroundStyle(HoopColor.text)
                HStack(spacing: 2) {
                    HoopLiveDot(tint: HoopColor.recoveryHigh, active: live.connected)
                    Text(rowStatusText)
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(HoopColor.textTertiary)
        }
        .padding(.horizontal, HoopSpace.l + 2)
        .padding(.vertical, HoopSpace.l)
        .background(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous).fill(HoopColor.surface))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusText: String {
        if live.backfilling { return String(localized: "Syncing") }
        if live.bonded { return String(localized: "Connected") }
        if live.connected { return String(localized: "Connecting…") }
        return String(localized: "Not connected")
    }

    private var rowStatusText: String {
        if let at = live.lastSyncedAt, !live.backfilling {
            return statusText + " · " + String(localized: "Synced \(HoopFormat.relative(Date(timeIntervalSince1970: at)))")
        }
        return statusText
    }

    private var accessibilityText: String {
        var parts = [selectedModelRaw, statusText]
        if let pct {
            parts.append(live.connected
                         ? String(localized: "Battery \(Int(pct.rounded())) percent")
                         : String(localized: "Battery \(Int(pct.rounded())) percent when last connected"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Explainers

enum HoopInfoTopic: String, Identifiable {
    case recovery, strain, sleep, vitals
    var id: String { rawValue }
}

struct HoopInfoSheet: View {
    let topic: HoopInfoTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HoopSpace.l) {
                    HStack(spacing: HoopSpace.m) {
                        glyph.frame(width: 24, height: 24)
                        Text(title)
                            .font(HoopFont.title)
                            .foregroundStyle(HoopColor.text)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(paragraphs, id: \.self) { p in
                        Text(p)
                            .font(HoopFont.body)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Hoop computes every number on this iPhone from your strap's raw data. They are estimates for wellness, not medical measurements.")
                        .font(HoopFont.footnote)
                        .foregroundStyle(HoopColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, HoopSpace.s)
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// A tiny hoop in the topic's colour; recovery shows its three bands.
    @ViewBuilder
    private var glyph: some View {
        switch topic {
        case .recovery:
            ZStack {
                band(0.0, 0.31, HoopColor.recoveryLow)
                band(0.345, 0.645, HoopColor.recoveryMid)
                band(0.68, 0.965, HoopColor.recoveryHigh)
            }
            .rotationEffect(.degrees(-90))
        case .strain: HoopRing(progress: 0.7, tint: HoopColor.strain, lineWidth: 3.5)
        case .sleep: HoopRing(progress: 0.82, tint: HoopColor.sleep, lineWidth: 3.5)
        case .vitals:
            Image(systemName: "heart.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HoopColor.heart)
        }
    }

    private func band(_ from: Double, _ to: Double, _ color: Color) -> some View {
        Circle()
            .inset(by: 1.75)
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
    }

    private var title: String {
        switch topic {
        case .recovery: return String(localized: "Recovery")
        case .strain: return String(localized: "Strain")
        case .sleep: return String(localized: "Sleep performance")
        case .vitals: return String(localized: "Vitals")
        }
    }

    private var paragraphs: [String] {
        switch topic {
        case .recovery:
            return [
                String(localized: "Recovery is how ready your body is to take on strain, from 0 to 100%. It compares last night's heart rate variability, resting heart rate and sleep with your own baseline."),
                String(localized: "Green (67% and up) means you're primed. Yellow (34–66%) is a steady day. Red (under 34%) means your body is asking for rest."),
                String(localized: "Hoop needs about four nights of wear to learn your baseline before the first score appears."),
            ]
        case .strain:
            return [
                String(localized: "Strain measures how hard your heart has worked today, on a 0–21 scale. It climbs quickly at first and becomes harder to build the higher it goes."),
                String(localized: "It's calculated from the time you spend in each heart-rate zone relative to your max heart rate. You can switch to a 0–100 scale in the You tab."),
            ]
        case .sleep:
            return [
                String(localized: "Sleep performance compares the sleep you got with the sleep you needed, based on your recent nights."),
                String(localized: "Stages are estimated from heart rate, heart rate variability and motion. Treat them as a guide, not a lab result."),
            ]
        case .vitals:
            return [
                String(localized: "HRV (heart rate variability) is the variation between heartbeats, measured while you sleep. Higher than your normal usually means you're well recovered."),
                String(localized: "Resting heart rate is your lowest sustained heart rate overnight. A rise above your normal can be an early sign of stress, illness or under-recovery."),
                String(localized: "Respiratory rate is your breaths per minute asleep, and is usually very stable, so a change is worth noticing."),
            ]
        }
    }
}
#endif
