#if os(iOS)
import SwiftUI

// MARK: - Hoop design language
//
// Quiet dark. A true-black canvas, one ring (a "hoop") per screen carrying that screen's number, and
// everything else set in type. Colour is reserved for meaning: recovery runs red → amber → green, strain
// is blue, sleep is violet, the heart is coral and fuel is orange. Nothing else is coloured.
//
// Containers are few and soft: a faint lift of white with no border, so they read on black and on an
// elevated sheet alike. Hierarchy comes from size, weight and space rather than from boxes, icons or
// chips. Numbers are SF Pro Rounded with monospaced digits; prose is SF Pro at Dynamic Type sizes.
//
// Every Hoop screen draws from these tokens only, so the whole app can be re-tuned from this file.

enum HoopColor {
    // Canvas + surfaces
    static let canvas = Color.black
    /// The one container fill.
    static let surface = Color.white.opacity(0.075)
    /// Pressed rows, secondary buttons, inner wells.
    static let surfaceHigh = Color.white.opacity(0.13)
    static let hairline = Color.white.opacity(0.10)
    /// Unfilled part of rings and bars.
    static let track = Color.white.opacity(0.10)

    // Text
    static let text = Color(red: 0.961, green: 0.961, blue: 0.969)                          // #F5F5F7
    static let textSecondary = Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.62)
    static let textTertiary = Color(red: 0.922, green: 0.922, blue: 0.961).opacity(0.34)

    // Meaning
    static let recoveryHigh = Color(red: 0.188, green: 0.839, blue: 0.494)    // #30D67E
    static let recoveryMid = Color(red: 1.0, green: 0.769, blue: 0.263)       // #FFC443
    static let recoveryLow = Color(red: 1.0, green: 0.294, blue: 0.290)       // #FF4B4A
    static let strain = Color(red: 0.263, green: 0.565, blue: 1.0)            // #4390FF
    static let sleep = Color(red: 0.573, green: 0.502, blue: 1.0)             // #9280FF
    static let heart = Color(red: 1.0, green: 0.431, blue: 0.408)             // #FF6E68 coral
    static let energy = Color(red: 1.0, green: 0.608, blue: 0.259)            // #FF9B42

    /// Interactive chrome (toolbar buttons, links, pickers). Neutral, so colour keeps meaning data.
    static let accent = text

    // Brand: the app icon's ring, sampled from icon_1024.png. Used only by the logo and first run.
    static let brandGreen = Color(red: 0.157, green: 0.894, blue: 0.612)      // #28E49C
    static let brandCyan = Color(red: 0.349, green: 0.827, blue: 1.0)         // #59D3FF
    static let brandViolet = Color(red: 0.616, green: 0.580, blue: 1.0)       // #9D94FF
    static let brandCore = Color(red: 0.969, green: 0.973, blue: 0.980)       // #F7F8FA

    // Sleep stages: one tonal family, awake kept neutral.
    static let stageAwake = Color(red: 0.93, green: 0.93, blue: 0.96).opacity(0.62)
    static let stageREM = Color(red: 0.74, green: 0.64, blue: 1.0)            // #BDA3FF
    static let stageLight = Color(red: 0.47, green: 0.60, blue: 1.0)          // #7899FF
    static let stageDeep = Color(red: 0.38, green: 0.31, blue: 0.93)          // #614FED

    /// Recovery colour for a 0–100 score: red under 34, amber under 67, green above.
    static func recovery(_ pct: Double?) -> Color {
        guard let pct else { return textTertiary }
        if pct >= 67 { return recoveryHigh }
        if pct >= 34 { return recoveryMid }
        return recoveryLow
    }

    /// Battery colour: green, amber under 40%, red under 20%.
    static func battery(_ pct: Double?, charging: Bool = false) -> Color {
        guard let pct else { return textTertiary }
        if charging { return recoveryHigh }
        return pct < 20 ? recoveryLow : (pct < 40 ? recoveryMid : recoveryHigh)
    }
}

enum HoopFont {
    // Prose: Dynamic Type text styles, so every label scales with the reader's text size.
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.bold)
    static let title3 = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subhead = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2

    /// Fixed-size numerals, for the inside of rings where the geometry is fixed.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Numerals that scale with Dynamic Type, for values in rows and stats.
    static func value(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

enum HoopSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let section: CGFloat = 36
    /// Screen side margin.
    static let gutter: CGFloat = 20
    /// Inner padding of a surface.
    static let inset: CGFloat = 20
    static let radius: CGFloat = 24
    static let smallRadius: CGFloat = 16
}

// MARK: - Canvas

/// The app canvas: true black. Colour, when a screen has any, comes from its hero's glow instead.
struct HoopBackground: View {
    var body: some View {
        HoopColor.canvas.ignoresSafeArea()
    }
}

/// A soft pool of light in a domain colour, laid behind a hero ring so the one number on the screen is
/// also its one source of colour.
struct HoopGlow: View {
    let tint: Color
    var intensity: Double = 0.26

    var body: some View {
        GeometryReader { g in
            let r = max(g.size.width, g.size.height) / 2
            RadialGradient(colors: [tint.opacity(intensity), tint.opacity(intensity * 0.35), tint.opacity(0)],
                           center: .center, startRadius: 0, endRadius: r)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

/// The one container: a faint rounded lift with no border.
struct HoopSurface<Content: View>: View {
    var padding: CGFloat = HoopSpace.inset
    var radius: CGFloat = HoopSpace.radius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(HoopColor.surface))
    }
}

/// A section title between surfaces, with an optional trailing accessory.
struct HoopSectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(HoopFont.title3)
                .foregroundStyle(HoopColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: HoopSpace.s)
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.top, HoopSpace.section)
        .padding(.bottom, HoopSpace.m)
    }
}

/// A small, quiet label above a group of rows (settings-style screens).
struct HoopGroupLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(HoopFont.footnote.weight(.semibold))
            .foregroundStyle(HoopColor.textSecondary)
            .padding(.horizontal, 4)
            .padding(.top, HoopSpace.xxl)
            .padding(.bottom, HoopSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows stacked in one surface. Each row draws its own hairline; pass `last: true` to the final one.
struct HoopGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous).fill(HoopColor.surface))
            .clipShape(RoundedRectangle(cornerRadius: HoopSpace.radius, style: .continuous))
    }
}

/// A settings-style row: title (and optional subtitle), a trailing value, an optional chevron.
struct HoopRow: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var value: String? = nil
    var chevron = false
    var external = false
    var titleColor: Color = HoopColor.text
    var last = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the value moves under the title, as in Settings, instead of both wrapping.
        let stacked = typeSize.isAccessibilitySize
        HoopRowContainer(last: last) {
            HStack(spacing: HoopSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(HoopFont.body)
                        .foregroundStyle(titleColor)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if stacked, let value, !value.isEmpty {
                        Text(value)
                            .font(HoopFont.subhead)
                            .foregroundStyle(HoopColor.textSecondary)
                    }
                }
                Spacer(minLength: HoopSpace.s)
                if !stacked, let value, !value.isEmpty {
                    Text(value)
                        .font(HoopFont.body)
                        .foregroundStyle(HoopColor.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                if chevron || external {
                    Image(systemName: external ? "arrow.up.right" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(HoopColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// The frame every row shares: side padding, a comfortable minimum height and a trailing hairline.
struct HoopRowContainer<Content: View>: View {
    var last = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, HoopSpace.inset)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { HoopDivider().padding(.leading, HoopSpace.inset) }
            }
    }
}

/// A one-pixel hairline.
struct HoopDivider: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle().fill(HoopColor.hairline).frame(height: 1 / max(scale, 1))
    }
}

/// Highlights a tapped row the way a system list does.
struct HoopRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? HoopColor.surfaceHigh : Color.clear)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A whole-surface tap: a gentle dim and settle while pressed.
struct HoopPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Buttons

/// The one filled button on a screen. White by default; label in canvas black.
struct HoopPrimaryButtonStyle: ButtonStyle {
    var tint: Color = HoopColor.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HoopFont.headline)
            .foregroundStyle(HoopColor.canvas)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, HoopSpace.l)
            .background(Capsule().fill(tint))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.32)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A quieter capsule for second actions.
struct HoopSecondaryButtonStyle: ButtonStyle {
    var tint: Color = HoopColor.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HoopFont.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, HoopSpace.l)
            .background(Capsule().fill(configuration.isPressed ? HoopColor.surfaceHigh.opacity(1.4) : HoopColor.surfaceHigh))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A round icon button (close, info). Liquid Glass on iOS 26, a soft disc before it.
struct HoopIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(HoopColor.text)
                .frame(width: size, height: size)
                .hoopGlassCircle()
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
    }
}

// MARK: - Rings

/// The hoop: a round-capped arc over a faint track, filled with a calm spring. The stroke is inset so the
/// ring sits exactly inside its frame. Draws nothing for zero progress rather than a stray cap.
struct HoopRing: View {
    /// 0...1 (clamped).
    let progress: Double
    var tint: Color
    var lineWidth: CGFloat = 14
    var track: Color = HoopColor.track

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        let p = min(max(shown, 0), 1)
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(track, lineWidth: lineWidth)
            if p > 0.002 {
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: p)
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.62), tint],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360 * p)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .onAppear { set(progress, animated: true) }
        .onChange(of: progress) { _, new in set(new, animated: true) }
        .accessibilityHidden(true)
    }

    private func set(_ value: Double, animated: Bool) {
        let target = value.isFinite ? min(max(value, 0), 1) : 0
        guard animated, !reduceMotion else { shown = target; return }
        withAnimation(.spring(response: 1.0, dampingFraction: 0.9)) { shown = target }
    }
}

/// A slim horizontal progress bar.
struct HoopBar: View {
    /// 0...1
    let progress: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let p = progress.isFinite ? min(max(progress, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(HoopColor.track)
                if p > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height, g.size.width * p))
                }
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Sparkline

/// A small line of recent values; nil gaps are skipped and the latest point gets a dot.
struct HoopSparkline: View {
    let values: [Double?]
    var tint: Color = HoopColor.textSecondary
    var lineWidth: CGFloat = 1.5
    var fill = false

    var body: some View {
        GeometryReader { g in
            let points = plotted(in: g.size)
            ZStack {
                if points.count >= 2 {
                    if fill {
                        Path { p in
                            p.move(to: CGPoint(x: points[0].x, y: g.size.height))
                            for pt in points { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: points[points.count - 1].x, y: g.size.height))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                    }
                    Path { p in
                        p.move(to: points[0])
                        for pt in points.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    Circle().fill(tint).frame(width: lineWidth * 3, height: lineWidth * 3).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func plotted(in size: CGSize) -> [CGPoint] {
        let present = values.enumerated().compactMap { i, v in v.map { (i, $0) } }
        guard let lo = present.map(\.1).min(), let hi = present.map(\.1).max() else { return [] }
        let span = max(hi - lo, 0.0001)
        let n = max(values.count - 1, 1)
        let inset = lineWidth * 1.5
        return present.map { i, v in
            CGPoint(x: inset + (size.width - inset * 2) * CGFloat(i) / CGFloat(n),
                    y: inset + (size.height - inset * 2) * (1 - CGFloat((v - lo) / span)))
        }
    }
}

// MARK: - Numbers

/// A hero numeral with a small trailing symbol ("78%"), optically centred on the digits: an invisible twin
/// of the symbol on the leading side balances the visible one.
struct HoopHeroNumber: View {
    let value: String
    var symbol: String = ""
    var size: CGFloat = 78
    var color: Color = HoopColor.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if !symbol.isEmpty {
                Text(symbol).font(HoopFont.number(size * 0.33, .medium)).hidden()
            }
            Text(value)
                .font(HoopFont.number(size))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if !symbol.isEmpty {
                Text(symbol)
                    .font(HoopFont.number(size * 0.33, .medium))
                    .foregroundStyle(HoopColor.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// A number with its unit set smaller and quieter on the same baseline ("62 ms").
struct HoopValue: View {
    let value: String
    var unit: String = ""
    var font: Font = HoopFont.value(.title2)
    var unitFont: Font = HoopFont.footnote
    var color: Color = HoopColor.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(font)
                .foregroundStyle(value == HoopFormat.dash ? HoopColor.textTertiary : color)
                .contentTransition(.numericText())
            // A missing value is a lone dash: "– kcal" reads as broken rather than as empty.
            if !unit.isEmpty && value != HoopFormat.dash {
                Text(unit)
                    .font(unitFont)
                    .foregroundStyle(HoopColor.textSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// A label over a value, for inline stat rows (Bedtime · Woke · Efficiency).
struct HoopStat: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            HoopValue(value: value, unit: unit, font: HoopFont.value(.headline), unitFont: HoopFont.caption)
            Text(label)
                .font(HoopFont.footnote)
                .foregroundStyle(HoopColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Live indicator

/// A small dot that breathes while live. Still under Reduce Motion.
struct HoopLiveDot: View {
    var tint: Color = HoopColor.recoveryHigh
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active && !reduceMotion {
                Circle().fill(tint.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.6 : 0.6)
                    .opacity(pulse ? 0 : 1)
            }
            Circle().fill(active ? tint : HoopColor.textTertiary).frame(width: 6, height: 6)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard active, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Formatting helpers

enum HoopFormat {
    static let dash = "–"

    static func int(_ v: Double?) -> String {
        guard let v, v.isFinite else { return dash }
        return Int(v.rounded()).formatted()
    }

    static func hoursMinutes(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes > 0 else { return dash }
        let m = Int(minutes.rounded())
        // A no-break space keeps "8h 00m" on one line when a caption wraps.
        return m >= 60 ? "\(m / 60)h\u{00A0}\(String(format: "%02d", m % 60))m" : "\(m)m"
    }

    static func clock(_ ts: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(ts)).formatted(date: .omitted, time: .shortened)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return String(localized: "just now") }
        if s < 3600 { return String(localized: "\(Int(s / 60)) min ago") }
        if s < 86_400 { return String(localized: "\(Int(s / 3600)) h ago") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "Tuesday, 29 September" in the reader's locale.
    static func longDate(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

extension View {
    /// Standard Hoop screen margins.
    func hoopScreenPadding() -> some View {
        padding(.horizontal, HoopSpace.gutter)
    }

    /// A circle of Liquid Glass on iOS 26 and later; a soft disc before it.
    @ViewBuilder
    func hoopGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(Circle().fill(HoopColor.surfaceHigh))
        }
    }

    /// The date (or any context line) under a large navigation title, where the OS supports it.
    @ViewBuilder
    func hoopNavigationSubtitle(_ text: String) -> some View {
        if #available(iOS 26.0, *) {
            self.navigationSubtitle(text)
        } else {
            self
        }
    }

    /// The standard Hoop tab-root chrome: black canvas under a large title.
    func hoopTabRoot(_ title: LocalizedStringKey) -> some View {
        self
            .scrollIndicators(.hidden)
            .hoopSoftTopEdge()
            .background(HoopBackground())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }

    /// Pins `bar` to the bottom edge. On iOS 26 and later, content scrolling beneath it gets the system's
    /// soft scroll-edge effect; before that the bar sits on the standard bar material.
    @ViewBuilder
    func hoopBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .bottom) { bar() }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self.safeAreaInset(edge: .bottom) { bar().background(.bar) }
        }
    }

    /// Content fades softly under the navigation bar on iOS 26 and later, rather than meeting a hard rule.
    @ViewBuilder
    func hoopSoftTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
#endif
