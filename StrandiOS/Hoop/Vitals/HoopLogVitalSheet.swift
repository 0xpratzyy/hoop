#if os(iOS)
import SwiftUI
import UIKit

/// Log a reading Hoop can't take itself: weight, blood pressure, resting heart rate, blood glucose or body
/// temperature. A native form, like Fuel's sheets. Values are typed on the reader's units and stored in
/// kg, mmHg, bpm, mg/dL and °C.
struct HoopLogVitalSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var log = HoopVitalsLog.shared
    @ObservedObject private var plan = CutPlanStore.shared
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.whoop.rawValue
    @AppStorage(HoopVitalsPrefs.glucoseUnitKey) private var glucoseRaw = HoopGlucoseUnit.regionalDefault.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var kind: HoopManualVital
    @State private var first = ""
    @State private var second = ""
    @State private var at = Date()
    @FocusState private var focused: Field?

    private enum Field { case first, second }

    init(initial: HoopManualVital? = nil) {
        _kind = State(initialValue: initial ?? .weight)
    }

    private var units: HoopVitalUnits {
        HoopVitalUnits(systemRaw: unitSystemRaw, temperatureRaw: temperatureRaw,
                       effortRaw: effortScaleRaw, glucoseRaw: glucoseRaw)
    }

    private var vital: HoopVital { HoopVitalCatalog.vital(for: kind) }

    var body: some View {
        let u = units
        NavigationStack {
            Form {
                Section {
                    Picker("Vital", selection: $kind) {
                        ForEach(HoopManualVital.allCases) { Text($0.pickerTitle).tag($0) }
                    }
                }
                Section {
                    if kind == .bloodPressure {
                        field(String(localized: "Systolic"), text: $first, unit: "mmHg",
                              spokenUnit: vital.spokenUnit(u), focus: .first, keyboard: .numberPad)
                        field(String(localized: "Diastolic"), text: $second, unit: "mmHg",
                              spokenUnit: vital.spokenUnit(u), focus: .second, keyboard: .numberPad)
                    } else {
                        field(label, text: $first, unit: vital.unitLabel(u, compact: false),
                              spokenUnit: vital.spokenUnit(u), focus: .first,
                              keyboard: kind == .restingHeartRate ? .numberPad : .decimalPad)
                    }
                    if kind == .bloodGlucose {
                        Picker("Unit", selection: $glucoseRaw) {
                            ForEach(HoopGlucoseUnit.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    Text(footer)
                }
                Section {
                    DatePicker("When", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Log a vital")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(u) }
                        .fontWeight(.semibold)
                        .disabled(reading(u) == nil)
                }
            }
            .onAppear { reset() }
            .onChange(of: kind) { _, _ in reset() }
            .onChange(of: glucoseRaw) { _, _ in first = "" }
        }
        .presentationDetents([.medium, .large])
    }

    /// A labelled entry row, as in Apple Health's own forms: the name, the number typed at the trailing
    /// edge, then its unit. The whole row focuses the field.
    private func field(_ label: String, text: Binding<String>, unit: String, spokenUnit: String, focus: Field,
                       keyboard: UIKeyboardType) -> some View {
        HStack(spacing: HoopSpace.s) {
            Text(label)
                .foregroundStyle(HoopColor.text)
                .accessibilityHidden(true)   // the field below carries the same label
            Spacer(minLength: HoopSpace.s)
            TextField(label, text: text, prompt: Text(verbatim: ""))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($focused, equals: focus)
                .frame(maxWidth: 140)
                .accessibilityLabel(spokenUnit.isEmpty ? label : "\(label), \(spokenUnit)")
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(HoopColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = focus }
    }

    private var label: String {
        switch kind {
        case .weight: return String(localized: "Weight")
        case .restingHeartRate: return String(localized: "Heart rate")
        case .bloodGlucose: return String(localized: "Glucose")
        case .bodyTemperature: return String(localized: "Temperature")
        case .bloodPressure: return ""
        }
    }

    private var footer: String {
        switch kind {
        case .weight:
            return String(localized: "Saved as a Fuel weigh-in, so Fuel and Vitals always show the same weight.")
        case .bloodPressure:
            return String(localized: "Sit quietly for five minutes first, and use the same arm each time.")
        case .restingHeartRate:
            return String(localized: "Best taken lying down, first thing in the morning. Your strap's overnight resting heart rate is kept separately.")
        case .bloodGlucose:
            return String(localized: "Readings rise after meals, so it helps to note when you took it.")
        case .bodyTemperature:
            return String(localized: "From a thermometer. Your strap's skin temperature is kept separately.")
        }
    }

    // MARK: Parsing

    private func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// The typed reading in stored units, or nil while it's missing or outside any plausible range (a
    /// typo guard, not a clinical judgement).
    private func reading(_ u: HoopVitalUnits) -> (value: Double, value2: Double?)? {
        guard let a = number(first), a.isFinite else { return nil }
        switch kind {
        case .bloodPressure:
            guard let b = number(second), (60...260).contains(a), (30...160).contains(b), a > b else { return nil }
            return (a, b)
        case .weight:
            // The same bounds Fuel's weigh-in sheet accepts.
            let kg = vital.stored(fromDisplay: a, u)
            return kg > 20 && kg < 400 ? (kg, nil) : nil
        case .restingHeartRate:
            return (25...150).contains(a) ? (a, nil) : nil
        case .bloodGlucose:
            let mg = vital.stored(fromDisplay: a, u)
            return (20...600).contains(mg) ? (mg, nil) : nil
        case .bodyTemperature:
            let c = vital.stored(fromDisplay: a, u)
            return (32...44).contains(c) ? (c, nil) : nil
        }
    }

    private func save(_ u: HoopVitalUnits) {
        guard let r = reading(u) else { return }
        let kind = self.kind, when = min(at, Date())
        let plan = self.plan, profile = self.profile, log = self.log
        dismiss()
        // The writes land once the sheet has started closing: they change what the screen underneath
        // shows (Today's rows, the editor's list), and doing that while this sheet is still up cancels its
        // dismissal.
        Task { @MainActor in
            if kind == .weight {
                HoopWeighIn.log(kg: r.value, at: when, plan: plan, profile: profile)
            } else {
                log.add(kind, value: r.value, value2: r.value2, at: when)
            }
            // A vital just logged belongs on Today.
            HoopVitalsPrefs.show(kind.vitalID)
        }
    }

    private func reset() {
        second = ""
        at = Date()
        // Weight starts from the profile weight, as Fuel's weigh-in sheet does.
        first = kind == .weight && profile.weightKg > 0
            ? String(format: "%.1f", vital.display(profile.weightKg, units)) : ""
        focused = .first
    }
}
#endif
