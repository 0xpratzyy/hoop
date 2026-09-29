#if os(iOS)
import SwiftUI
import WhoopStore
import StrandAnalytics

/// Fuel: an optional weight goal built on the strap's calorie burn. How much you can eat today, what you
/// have logged, how that turns into fat lost, and whether you are on pace for the goal date.
struct HoopFuelView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var plan = CutPlanStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var activeToday: Double = 0
    @State private var showAddFood = false
    @State private var showGoal = false
    @State private var showWeight = false
    @State private var showSettings = false

    private var dayKey: String { Repository.localDayKey(Date()) }
    private var male: Bool { profile.sex != "female" }

    /// Estimated weight at the start of today (walked from the start weight by each logged day's deficit).
    private var startOfDayKg: Double {
        plan.estimatedKg(beforeDay: dayKey, heightCm: profile.heightCm, age: profile.age, male: male).kg
    }

    private var budget: CutPlanStore.Budget {
        plan.budget(weightKg: startOfDayKg, heightCm: profile.heightCm, age: profile.age, male: male,
                    activeKcal: activeToday, eaten: plan.eaten(day: dayKey))
    }

    private var burnedSoFar: Double { plan.dayBurn(maintenance: budget.maintenance, activeKcal: activeToday) }

    /// Estimated weight right now: start of day minus today's deficit so far.
    private var currentKg: Double {
        let todayLogged = !plan.entries(day: dayKey).isEmpty
        let today = todayLogged ? (burnedSoFar - plan.eaten(day: dayKey)) / CutPlanStore.kcalPerKgFat : 0
        return startOfDayKg - today
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if plan.configured {
                        budgetHero
                        HoopSectionHeader("Food") {
                            Text("\(plan.logged(day: dayKey).formatted()) kcal")
                                .font(HoopFont.value(.subheadline, .medium))
                                .foregroundStyle(HoopColor.textTertiary)
                        }
                        foodSurface
                        HoopSectionHeader("Energy balance")
                        balanceSurface
                        HoopSectionHeader("Goal") {
                            Button("Edit") { showGoal = true }
                                .font(HoopFont.subhead.weight(.semibold))
                                .foregroundStyle(HoopColor.textSecondary)
                                .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                                .accessibilityLabel("Edit goal")
                        }
                        goalSurface
                    } else {
                        setup
                    }
                }
                .hoopScreenPadding()
                .padding(.bottom, HoopSpace.xxl)
            }
            .hoopTabRoot("Fuel")
            .hoopNavigationSubtitle(HoopFormat.longDate())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HoopAskButton(topic: .fuel) }
                if plan.configured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                            .accessibilityLabel("Plan settings")
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            }
        }
        .sheet(isPresented: $showAddFood) { HoopAddFoodSheet(day: dayKey) }
        .sheet(isPresented: $showGoal) { HoopGoalSheet(currentKg: plan.configured ? currentKg : profile.weightKg) }
        .sheet(isPresented: $showWeight) { HoopWeighInSheet() }
        .sheet(isPresented: $showSettings) { HoopPlanSettingsSheet(weightKg: startOfDayKg) }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 0) {
            ZStack {
                HoopRing(progress: 0.68, tint: HoopColor.energy, lineWidth: 12)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(HoopColor.energy)
            }
            .frame(width: 116, height: 116)
            .background { HoopGlow(tint: HoopColor.energy, intensity: 0.22).frame(width: 340, height: 340) }
            .padding(.top, HoopSpace.l)
            .accessibilityHidden(true)

            VStack(spacing: HoopSpace.m) {
                Text("Hit a weight goal with your strap")
                    .font(HoopFont.title)
                    .foregroundStyle(HoopColor.text)
                Text("Set a goal weight and a date. Hoop works out how much you can eat each day, counts the calories your strap sees you burn, and shows whether you're on pace.")
                    .font(HoopFont.callout)
                    .foregroundStyle(HoopColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, HoopSpace.xxl)

            HoopGroup {
                feature("A daily food allowance that adapts to your workouts")
                feature("Calories turned into grams of fat lost")
                feature("An estimated weight, even without a scale", last: true)
            }
            .padding(.top, HoopSpace.xl + 4)

            Button { showGoal = true } label: { Text("Set my goal") }
                .buttonStyle(HoopPrimaryButtonStyle())
                .padding(.top, HoopSpace.xl + 4)
            Text("Optional. Your log stays on this iPhone.")
                .font(HoopFont.caption)
                .foregroundStyle(HoopColor.textTertiary)
                .padding(.top, HoopSpace.m)
        }
    }

    private func feature(_ text: LocalizedStringKey, last: Bool = false) -> some View {
        HoopRowContainer(last: last) {
            HStack(alignment: .firstTextBaseline, spacing: HoopSpace.m) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(HoopColor.energy)
                    .accessibilityHidden(true)
                Text(text)
                    .font(HoopFont.callout)
                    .foregroundStyle(HoopColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Budget

    private var budgetHero: some View {
        let b = budget
        let over = b.remaining < 0
        let tint = over ? HoopColor.recoveryLow : HoopColor.energy
        let stacked = typeSize.isAccessibilitySize
        let statsLayout = stacked ? AnyLayout(VStackLayout(spacing: HoopSpace.l)) : AnyLayout(HStackLayout(spacing: 0))
        return VStack(spacing: 0) {
            ZStack {
                HoopRing(progress: b.eaten / max(b.allowance, 1), tint: tint, lineWidth: 16)
                VStack(spacing: 0) {
                    Text(HoopFormat.int(abs(b.remaining)))
                        .font(HoopFont.number(54))
                        .foregroundStyle(over ? HoopColor.recoveryLow : HoopColor.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(over ? "kcal over" : "kcal left")
                        .font(HoopFont.subhead)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .padding(.horizontal, 28)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(width: 224, height: 224)
            .background { HoopGlow(tint: tint).frame(width: 440, height: 440) }
            .padding(.top, HoopSpace.l)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(over
                                ? String(localized: "\(HoopFormat.int(abs(b.remaining))) kilocalories over today's allowance")
                                : String(localized: "\(HoopFormat.int(b.remaining)) kilocalories left today"))

            statsLayout {
                HoopStat(label: "Eaten", value: HoopFormat.int(b.eaten))
                if !stacked { statDivider }
                HoopStat(label: "Workout", value: "\(HoopFormat.int(b.workoutDone)) / \(HoopFormat.int(b.workoutTarget))")
                if !stacked { statDivider }
                HoopStat(label: "Allowance", value: HoopFormat.int(b.allowance))
            }
            .padding(.top, HoopSpace.xxl)

            if b.workoutBonus > 0 || plan.logBuffer > 0 {
                VStack(spacing: 2) {
                    if b.workoutBonus > 0 {
                        Text("Includes \(HoopFormat.int(b.workoutBonus)) kcal earned by extra workout")
                    }
                    if plan.logBuffer > 0 {
                        Text("Logged food counts \(Int((plan.logBuffer * 100).rounded()))% higher, as a buffer")
                    }
                }
                .font(HoopFont.caption)
                .foregroundStyle(HoopColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, HoopSpace.m)
            }

            proteinBar
                .padding(.top, HoopSpace.xxl)

            Button { showAddFood = true } label: { Label("Log food", systemImage: "plus") }
                .buttonStyle(HoopPrimaryButtonStyle())
                .padding(.top, HoopSpace.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(HoopColor.hairline).frame(width: 1, height: 30)
    }

    private var proteinBar: some View {
        let got = plan.protein(day: dayKey)
        let target = max(plan.proteinTarget, 1)
        return VStack(alignment: .leading, spacing: HoopSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Protein")
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textSecondary)
                Spacer()
                Text("\(Int(got.rounded())) / \(Int(target.rounded())) g")
                    .font(HoopFont.value(.footnote))
                    .foregroundStyle(HoopColor.text)
            }
            HoopBar(progress: got / target, tint: HoopColor.text.opacity(0.85), height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Food

    private var foodSurface: some View {
        let entries = plan.entries(day: dayKey)
        return HoopGroup {
            if entries.isEmpty {
                HoopRowContainer(last: true) {
                    Text("Nothing logged yet today.")
                        .font(HoopFont.callout)
                        .foregroundStyle(HoopColor.textTertiary)
                }
            }
            ForEach(entries) { e in
                HoopRowContainer(last: e.id == entries.last?.id) {
                    HStack(spacing: HoopSpace.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name)
                                .font(HoopFont.body)
                                .foregroundStyle(HoopColor.text)
                            Text(e.at.formatted(date: .omitted, time: .shortened))
                                .font(HoopFont.footnote)
                                .foregroundStyle(HoopColor.textSecondary)
                        }
                        Spacer(minLength: HoopSpace.s)
                        VStack(alignment: .trailing, spacing: 2) {
                            HoopValue(value: "\(e.kcal)", unit: "kcal", font: HoopFont.value(.body), unitFont: HoopFont.caption)
                            if let p = e.protein {
                                Text("\(Int(p.rounded())) g protein")
                                    .font(HoopFont.footnote)
                                    .foregroundStyle(HoopColor.textTertiary)
                            }
                        }
                        Menu {
                            Button(role: .destructive) { plan.removeFood(e.id, day: dayKey) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(HoopColor.textTertiary)
                                .frame(width: 32, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Options for \(e.name)")
                    }
                }
            }
        }
    }

    // MARK: Balance

    private struct DayBar: Identifiable {
        let id: String
        let date: Date
        let deficit: Double?
        let isToday: Bool
    }

    private func weekDays(maintenance: Double) -> [DayBar] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { back -> DayBar? in
            guard let date = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let k = Repository.localDayKey(date)
            var deficit: Double?
            if !plan.entries(day: k).isEmpty {
                let burn = k == dayKey ? burnedSoFar
                    : plan.dayBurn(maintenance: maintenance, activeKcal: plan.activeByDay[k] ?? 0)
                deficit = burn - plan.eaten(day: k)
            }
            return DayBar(id: k, date: date, deficit: deficit, isToday: back == 0)
        }
    }

    private var balanceSurface: some View {
        let b = budget
        let deficit = burnedSoFar - b.eaten
        let good = deficit >= 0
        let tint = good ? HoopColor.recoveryHigh : HoopColor.recoveryLow
        let days = weekDays(maintenance: b.maintenance)
        let weekKcal = days.compactMap(\.deficit).reduce(0, +)
        let peak = max(days.compactMap { $0.deficit.map(abs) }.max() ?? 1, 1)
        return HoopSurface(padding: HoopSpace.l + 2) {
            VStack(alignment: .leading, spacing: HoopSpace.l) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: HoopSpace.m) {
                        equationTerm(HoopFormat.int(burnedSoFar), "burned")
                        equationSign("−")
                        equationTerm(HoopFormat.int(b.eaten), "eaten")
                        equationSign("=")
                        equationTerm(HoopFormat.int(abs(deficit)), good ? "deficit" : "surplus")
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: HoopSpace.s) {
                        equationTerm(HoopFormat.int(burnedSoFar), "burned")
                        equationTerm(HoopFormat.int(b.eaten), "eaten")
                        equationTerm(HoopFormat.int(abs(deficit)), good ? "deficit" : "surplus")
                    }
                }
                .accessibilityElement(children: .combine)

                HStack(alignment: .firstTextBaseline, spacing: HoopSpace.s) {
                    Text(fatText(deficit))
                        .font(HoopFont.value(.largeTitle))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text(good ? "of fat burned today" : "stored today")
                        .font(HoopFont.subhead)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .accessibilityElement(children: .combine)

                HoopDivider()

                VStack(alignment: .leading, spacing: HoopSpace.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last 7 days")
                            .font(HoopFont.footnote)
                            .foregroundStyle(HoopColor.textSecondary)
                        Spacer()
                        if days.contains(where: { $0.deficit != nil }) {
                            Text(String(format: "%@%.2f kg", weekKcal >= 0 ? "−" : "+", abs(weekKcal) / CutPlanStore.kcalPerKgFat))
                                .font(HoopFont.value(.footnote))
                                .foregroundStyle(weekKcal >= 0 ? HoopColor.recoveryHigh : HoopColor.recoveryLow)
                        }
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(days) { d in
                            VStack(spacing: HoopSpace.s) {
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(HoopColor.track.opacity(0.6))
                                    if let v = d.deficit {
                                        Capsule()
                                            .fill(v >= 0 ? HoopColor.recoveryHigh : HoopColor.recoveryLow)
                                            .frame(height: max(12, 56 * abs(v) / peak))
                                    }
                                }
                                .frame(width: 12, height: 56)
                                Text(d.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(HoopFont.caption2.weight(d.isToday ? .semibold : .regular))
                                    .foregroundStyle(d.isToday ? HoopColor.text : HoopColor.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(balanceAccessibility(days))
                }

                Text("1 kg of body fat ≈ 7,700 kcal")
                    .font(HoopFont.caption)
                    .foregroundStyle(HoopColor.textTertiary)
            }
        }
    }

    private func balanceAccessibility(_ days: [DayBar]) -> String {
        let parts = days.map { d -> String in
            let day = d.date.formatted(.dateTime.weekday(.wide))
            guard let v = d.deficit else { return String(localized: "\(day) nothing logged") }
            return v >= 0
                ? String(localized: "\(day) \(HoopFormat.int(v)) kilocalorie deficit")
                : String(localized: "\(day) \(HoopFormat.int(abs(v))) kilocalorie surplus")
        }
        return String(localized: "Energy balance, last seven days: \(parts.joined(separator: ", "))")
    }

    private func equationTerm(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(HoopFont.value(.title3))
                .foregroundStyle(HoopColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(HoopFont.caption)
                .foregroundStyle(HoopColor.textTertiary)
        }
        .fixedSize()
    }

    private func equationSign(_ sign: String) -> some View {
        Text(sign)
            .font(HoopFont.value(.title3, .regular))
            .foregroundStyle(HoopColor.textTertiary)
            .accessibilityHidden(true)
    }

    private func fatText(_ kcal: Double) -> String {
        let g = abs(kcal) / CutPlanStore.kcalPerKgFat * 1000
        return g < 1000 ? "\(Int(g.rounded())) g" : String(format: "%.2f kg", g / 1000)
    }

    // MARK: Goal

    /// Average burn − food over the last seven complete logged days; under two days, the plan stands in.
    private var pace: (kcal: Double, fromPlan: Bool) {
        let maintenance = budget.maintenance
        let recent = plan.loggedDays.filter { $0 < dayKey && $0 >= plan.startDay }.suffix(7)
        guard recent.count >= 2 else { return (budget.requiredDeficit, true) }
        let total = recent.reduce(0.0) { sum, k in
            sum + plan.dayBurn(maintenance: maintenance, activeKcal: plan.activeByDay[k] ?? 0) - plan.eaten(day: k)
        }
        return (total / Double(recent.count), false)
    }

    private var goalSurface: some View {
        let current = currentKg
        let toLose = max(current - plan.goalKg, 0)
        let reached = current <= plan.goalKg
        let span = max(plan.startKg - plan.goalKg, 0.1)
        let done = min(max((plan.startKg - current) / span, 0), 1)
        return HoopSurface(padding: HoopSpace.l + 2) {
            VStack(alignment: .leading, spacing: HoopSpace.l) {
                VStack(alignment: .leading, spacing: 4) {
                    if reached {
                        Text("Goal reached")
                            .font(HoopFont.value(.title))
                            .foregroundStyle(HoopColor.text)
                    } else {
                        HoopValue(value: String(format: "%.1f", toLose), unit: String(localized: "kg to go"),
                                  font: HoopFont.value(.title), unitFont: HoopFont.subhead)
                    }
                    Text("\(String(format: "%.1f", plan.goalKg)) kg by \(plan.targetDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(HoopFont.subhead)
                        .foregroundStyle(HoopColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: HoopSpace.s) {
                    HoopBar(progress: done, tint: HoopColor.recoveryHigh, height: 6)
                    HStack {
                        Text(String(format: "%.1f kg", plan.startKg))
                        Spacer()
                        Text(String(format: "Now ~%.1f kg", current)).foregroundStyle(HoopColor.textSecondary)
                        Spacer()
                        Text(String(format: "%.1f kg", plan.goalKg))
                    }
                    .font(HoopFont.value(.caption, .medium))
                    .foregroundStyle(HoopColor.textTertiary)
                }
                .accessibilityElement(children: .combine)
                HoopDivider()
                statusLine(current: current)
                Button { showWeight = true } label: { Label("Log weight", systemImage: "scalemass") }
                    .buttonStyle(HoopSecondaryButtonStyle())
            }
        }
    }

    private func statusLine(current: Double) -> some View {
        let p = pace
        let eta = plan.projectedGoalDate(currentKg: current, avgDailyDeficit: p.kcal)
        let cal = Calendar.current
        let late = eta.map { cal.dateComponents([.day], from: cal.startOfDay(for: plan.targetDate), to: cal.startOfDay(for: $0)).day ?? 0 }
        let when = eta.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
        let (text, tint): (String, Color) = {
            if current <= plan.goalKg { return (String(localized: "Done. Set a new goal any time."), HoopColor.recoveryHigh) }
            if p.fromPlan { return (String(localized: "Log two full days to see your pace."), HoopColor.textTertiary) }
            guard let late else { return (String(localized: "Not losing lately: eat a little less or move more."), HoopColor.recoveryLow) }
            if late <= 0 { return (String(localized: "On track to arrive \(when)."), HoopColor.recoveryHigh) }
            return (String(localized: "\(late) days behind: arriving \(when)."), HoopColor.recoveryMid)
        }()
        return HStack(alignment: .firstTextBaseline, spacing: HoopSpace.s) {
            Circle().fill(tint).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            Text(text)
                .font(HoopFont.subhead.weight(.medium))
                .foregroundStyle(HoopColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Data

    private func load() async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let hr = await repo.hrSamples(from: Int(start.timeIntervalSince1970), to: Int(Date().timeIntervalSince1970), limit: 200_000)
        let up = UserProfile(weightKg: startOfDayKg, heightCm: profile.heightCm, age: Double(profile.age), sex: profile.sex)
        if hr.isEmpty {
            activeToday = 0
        } else {
            activeToday = Calories.estimateDayEnergy(hr, profile: up, hrmax: Double(profile.hrMax),
                                                     restingHR: repo.today?.restingHr.map(Double.init)).activeKcal
        }
        guard plan.configured else { return }
        // Workout kcal for past logged days since the plan started, computed once per day.
        for offset in 1..<120 {
            guard let dStart = cal.date(byAdding: .day, value: -offset, to: start),
                  let dEnd = cal.date(byAdding: .day, value: 1, to: dStart) else { continue }
            let key = Repository.localDayKey(dStart)
            if key < plan.startDay { break }
            guard plan.activeByDay[key] == nil, !plan.entries(day: key).isEmpty else { continue }
            let dayHr = await repo.hrSamples(from: Int(dStart.timeIntervalSince1970), to: Int(dEnd.timeIntervalSince1970) - 1, limit: 200_000)
            let resting = repo.days.last(where: { $0.day == key })?.restingHr.map(Double.init)
            let e = Calories.estimateDayEnergy(dayHr, profile: up, hrmax: Double(profile.hrMax), restingHR: resting)
            plan.setActive(e.activeKcal, day: key)
        }
    }
}

// MARK: - Sheets

struct HoopAddFoodSheet: View {
    let day: String
    @ObservedObject private var plan = CutPlanStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @FocusState private var kcalFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                HoopAIFoodAssist { estimate in
                    name = estimate.name
                    kcal = "\(estimate.kcal)"
                    protein = estimate.protein.map { String(format: "%.0f", $0) } ?? ""
                }
                Section {
                    TextField("What did you eat?", text: $name)
                    TextField("Calories", text: $kcal)
                        .keyboardType(.numberPad)
                        .focused($kcalFocused)
                    TextField("Protein in grams (optional)", text: $protein)
                        .keyboardType(.decimalPad)
                }
                let recent = plan.recentFoods()
                if !recent.isEmpty {
                    Section("Tap to add again") {
                        ForEach(recent) { f in
                            Button {
                                plan.addFood(name: f.name, kcal: f.kcal, protein: f.protein, day: day)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(f.name).foregroundStyle(HoopColor.text)
                                    Spacer()
                                    Text(f.protein.map { "\(f.kcal) kcal · \(Int($0.rounded())) g" } ?? "\(f.kcal) kcal")
                                        .font(HoopFont.value(.body, .regular))
                                        .foregroundStyle(HoopColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        plan.addFood(name: name, kcal: Int(kcal) ?? 0,
                                     protein: Double(protein.replacingOccurrences(of: ",", with: ".")), day: day)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled((Int(kcal) ?? 0) <= 0)
                }
            }
            .onAppear { if !HoopAI.shared.isConnected { kcalFocused = true } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct HoopWeighInSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var plan = CutPlanStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Weight in kg", text: $kg).keyboardType(.decimalPad)
                } footer: {
                    Text("If you weigh yourself, enter it here and Hoop's weight estimate restarts from it.")
                }
                if !plan.weighIns.isEmpty {
                    Section("History") {
                        ForEach(plan.weighIns.reversed().prefix(14)) { w in
                            HStack {
                                Text(w.at.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text(String(format: "%.1f kg", w.kg))
                                    .font(HoopFont.value(.body, .regular))
                                    .foregroundStyle(HoopColor.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parsed {
                            plan.logWeight(v)
                            profile.weightKg = v
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsed == nil)
                }
            }
            .onAppear { kg = String(format: "%.1f", profile.weightKg) }
        }
        .presentationDetents([.medium, .large])
    }

    private var parsed: Double? {
        Double(kg.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 20 && $0 < 400 ? $0 : nil }
    }
}

/// Set or change the goal: current weight (first time), goal weight, date, and how the deficit splits
/// between eating less and moving more, with a live preview of what each day asks for.
struct HoopGoalSheet: View {
    let currentKg: Double
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var plan = CutPlanStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var startKg = 80.0
    @State private var goalKg = 75.0
    @State private var date = Date()
    @State private var share = 0.3

    private static var earliest: Date { Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date() }

    var body: some View {
        let male = profile.sex != "female"
        let weight = plan.configured ? currentKg : startKg
        let b = plan.budget(weightKg: weight, heightCm: profile.heightCm, age: profile.age, male: male,
                            activeKcal: 0, eaten: 0, goalKg: goalKg, targetDate: date, workoutShare: share)
        let tooFast = b.kgPerWeek > weight * 0.01
        return NavigationStack {
            Form {
                if !plan.configured {
                    Section {
                        stepperRow("Your weight now", value: $startKg, range: 35...250)
                    }
                }
                Section {
                    stepperRow("Goal weight", value: $goalKg, range: 35...max(35, weight - 0.5))
                } footer: {
                    Text(String(format: "%.1f kg to lose", max(weight - goalKg, 0)))
                }
                Section("Reach it by") {
                    DatePicker("Reach it by", selection: $date, in: Self.earliest..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(HoopColor.energy)
                }
                Section("Deficit from food vs. workouts") {
                    Picker("Split", selection: $share) {
                        Text("Food").tag(0.0)
                        Text("80/20").tag(0.2)
                        Text("70/30").tag(0.3)
                        Text("60/40").tag(0.4)
                        Text("50/50").tag(0.5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section {
                    previewRow("Eat per day", "\(HoopFormat.int(b.allowance)) kcal")
                    previewRow("Workout burn", "\(HoopFormat.int(b.workoutTarget)) kcal")
                    previewRow("Daily deficit", "\(HoopFormat.int(b.requiredDeficit)) kcal")
                    previewRow("Per week", String(format: "%.2f kg", b.kgPerWeek),
                               color: tooFast ? HoopColor.recoveryLow : HoopColor.text)
                } header: {
                    Text("Each day")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if tooFast {
                            Label("Faster than 1% of body weight a week. Consider a later date.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(HoopColor.recoveryLow)
                        }
                        if b.floorHit {
                            Label("Food is at the safe floor; the rest of the deficit moved to workouts.", systemImage: "info.circle.fill")
                                .foregroundStyle(HoopColor.recoveryMid)
                        }
                    }
                }
            }
            .navigationTitle(plan.configured ? "Edit goal" : "Your goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(goalKg >= weight)
                }
            }
            .onAppear {
                startKg = (profile.weightKg * 2).rounded() / 2
                goalKg = plan.configured ? plan.goalKg : max(35, ((profile.weightKg - 5) * 2).rounded() / 2)
                let defaultDate = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
                date = plan.configured ? max(plan.targetDate, Self.earliest) : defaultDate
                share = [0.0, 0.2, 0.3, 0.4, 0.5].contains(plan.workoutShare) ? plan.workoutShare : 0.3
            }
        }
    }

    private func save() {
        if !plan.configured {
            plan.startKg = startKg
            plan.startDay = Repository.localDayKey(Date())
            profile.weightKg = startKg
        }
        plan.goalKg = goalKg
        plan.targetDate = date
        plan.workoutShare = share
        plan.configured = true
        dismiss()
    }

    private func stepperRow(_ label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(HoopFont.footnote)
                    .foregroundStyle(HoopColor.textSecondary)
                Text(String(format: "%.1f kg", value.wrappedValue))
                    .font(HoopFont.value(.title2))
                    .foregroundStyle(HoopColor.text)
                    .contentTransition(.numericText())
            }
            Spacer()
            Stepper(label, value: value, in: range, step: 0.5).labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func previewRow(_ label: LocalizedStringKey, _ value: String, color: Color = HoopColor.text) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(HoopFont.value(.body))
                .foregroundStyle(color)
        }
    }
}

struct HoopPlanSettingsSheet: View {
    let weightKg: Double
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var plan = CutPlanStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    Picker("Protein target", selection: $plan.proteinPerKg) {
                        ForEach([1.6, 2.0, 2.2], id: \.self) { v in
                            Text(String(format: "%.1f g/kg · %.0f g", v, v * plan.goalKg)).tag(v)
                        }
                    }
                    Picker("Logging buffer", selection: $plan.logBuffer) {
                        Text("Off").tag(0.0)
                        Text("+10%").tag(0.10)
                        Text("+20%").tag(0.20)
                        Text("+30%").tag(0.30)
                    }
                    Picker("Eat back extra workout", selection: $plan.workoutEatBack) {
                        Text("None").tag(0.0)
                        Text("Half").tag(0.5)
                        Text("All").tag(1.0)
                    }
                }
                Section {
                    let b = plan.budget(weightKg: weightKg, heightCm: profile.heightCm, age: profile.age,
                                        male: profile.sex != "female", activeKcal: 0, eaten: 0)
                    row("Resting burn (BMR)", "\(HoopFormat.int(b.bmr)) kcal")
                    row("Maintenance", "\(HoopFormat.int(b.maintenance)) kcal")
                    row("Daily deficit", "\(HoopFormat.int(b.requiredDeficit)) kcal")
                    row("Food allowance", "\(HoopFormat.int(b.allowance)) kcal")
                    row("Workout target", "\(HoopFormat.int(b.workoutTarget)) kcal")
                } header: {
                    Text("Your numbers")
                } footer: {
                    Text("BMR uses Mifflin–St Jeor; maintenance assumes a desk day (×1.2). The logging buffer counts every logged calorie a little higher, because most people under-log.")
                }
                Section {
                    Button("Turn off Fuel", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Turn off Fuel?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Turn off", role: .destructive) {
                    plan.configured = false
                    dismiss()
                }
            } message: {
                Text("Your food log and weigh-ins are kept, so you can pick up where you left off.")
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(HoopFont.value(.body, .regular))
                .foregroundStyle(HoopColor.textSecondary)
        }
    }
}
#endif
