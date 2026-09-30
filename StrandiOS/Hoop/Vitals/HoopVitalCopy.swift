#if os(iOS)
import SwiftUI

/// What each vital means, in plain words, and the one colour its chart may use.
enum HoopVitalCopy {
    /// One paragraph for the detail screen. General wellness context, never a diagnosis.
    static func explanation(_ v: HoopVital) -> String {
        if let kind = v.manual { return manual(kind) }
        switch v.key {
        case "hrv":
            return String(localized: "Heart rate variability is the tiny variation in time between one heartbeat and the next, measured while you sleep. It reflects how settled your nervous system is. HRV is very personal, so compare it with your own normal rather than anyone else's: higher than usual generally means you've recovered well, while a drop can follow hard training, a short night, alcohol, stress or illness.")
        case "rhr":
            return String(localized: "Resting heart rate is your lowest sustained heart rate while you sleep, and it tends to fall as your fitness improves. A rise of a few beats above your normal, especially over several nights, can be an early sign of stress, illness, alcohol or not enough recovery.")
        case "resp_rate":
            return String(localized: "Respiratory rate is how many breaths you take per minute while asleep. For most adults it sits somewhere between 12 and 20 and barely changes from night to night, so a clear rise is worth noticing: it can come with illness, a hard block of training or poor sleep.")
        case "spo2":
            return String(localized: "Blood oxygen (SpO₂) is the share of the haemoglobin in your blood that is carrying oxygen, averaged across the night. Most healthy people sit between 95 and 100%. Wrist readings are less precise than a fingertip clip, so look at the trend over several nights rather than at a single number.")
        case "skin_temp":
            return String(localized: "Skin temperature is measured at your wrist while you sleep. Hoop shows it as the difference from your own baseline once it has learned one; imported history can show the temperature itself. Small shifts from night to night are normal. A clear rise can come with illness, alcohol, a warm room or the menstrual cycle, and means most alongside your HRV and resting heart rate.")
        case "vo2max_est":
            return String(localized: "VO₂ max is the most oxygen your body can use during hard exercise, in millilitres per kilogram of body weight per minute, and one of the best single markers of cardiovascular fitness. Hoop estimates it from your heart rate and your profile rather than measuring it on a treadmill, so treat it as a guide. It rises slowly with regular cardio.")
        case "vo2max":
            return String(localized: "VO₂ max is the most oxygen your body can use during hard exercise, in millilitres per kilogram of body weight per minute, and one of the best single markers of cardiovascular fitness. This is the estimate Apple Health holds, usually worked out from outdoor walks and runs with an Apple Watch.")
        case "fitness_age":
            return String(localized: "Fitness age compares your estimated cardiovascular fitness (VO₂ max) with what's typical at different ages. Below your real age means your heart and lungs are fitter than average for your age. It moves slowly, over weeks of training.")
        case "vitality":
            return String(localized: "Vitality is a 0–100 wellness score built from habits that large studies link with long-term health: fitness, resting heart rate, HRV, sleep and how regularly you sleep. 50 means typical for your age; higher is better. It's a wellness trend, not a medical measure, and changes slowly.")
        case "body_age":
            return String(localized: "Body age turns the same inputs as Vitality (fitness, resting heart rate, HRV and sleep) into years: your real age, older or younger depending on how those compare with what's typical. It's a wellness trend, not a biological or clinical age.")
        case "recovery":
            return String(localized: "Recovery is how ready your body is to take on strain, from 0 to 100%. It compares last night's heart rate variability, resting heart rate and sleep with your own baseline. Green (67% and up) means you're primed, yellow (34–66%) is a steady day, and red (under 34%) means your body is asking for rest.")
        case "strain":
            return String(localized: "Strain measures how hard your heart has worked in a day, on a 0–21 scale (or 0–100 if you've chosen that in You). It builds from the time you spend at higher heart rates relative to your maximum, and gets harder to raise the higher it goes. Today's value keeps climbing until the day ends.")
        case "sleep_performance":
            return String(localized: "Sleep performance is how restorative last night was, from 0 to 100%. It weighs how long you slept against what you needed, how efficiently you slept, your deep and REM sleep, and how regular your timing was.")
        case "avg_hr":
            return String(localized: "Your average heart rate across the whole day, awake and asleep. It moves with activity, stress, heat, caffeine and illness, so it's most useful as a trend.")
        case "max_hr":
            return String(localized: "The highest heart rate recorded during the day. On hard training days it shows how close you came to your maximum; on quiet days it's usually a brisk walk or a flight of stairs.")
        case "in_bed_min":
            return String(localized: "Time in bed runs from when you settled down to sleep until you got up, including time awake. A big gap between this and your time asleep usually means a restless night or a long time falling asleep.")
        case "sleep_total_min":
            return String(localized: "Time asleep adds up your light, deep and REM sleep, leaving out time awake in bed. Most adults need somewhere between seven and nine hours.")
        case "sleep_score":
            return String(localized: "Sleep score as your Mi Band worked it out, from 0 to 100. Higher means a better night by the band's own measure.")
        case "hours_vs_needed_pct":
            return String(localized: "How much of your sleep need you actually slept, as a percentage. Your need grows with the previous day's strain and with any sleep debt you're carrying.")
        case "sleep_consistency":
            return String(localized: "Sleep consistency is how similar your bed and wake times have been over recent days. Regular timing keeps your body clock steady and tends to make sleep more restorative.")
        case "restorative_pct":
            return String(localized: "Restorative sleep is the share of your night spent in deep and REM sleep, the stages in which your body and brain do most of their repair.")
        case "restorative_min":
            return String(localized: "Restorative sleep time is how long you spent in deep and REM sleep, the stages in which your body and brain do most of their repair.")
        case "sleep_efficiency":
            return String(localized: "Sleep efficiency is the share of your time in bed that you actually spent asleep. Around 85% or more is generally considered good.")
        case "sleep_deep_min":
            return String(localized: "Deep, or slow-wave, sleep is when your body does most of its physical repair and your heart rate is at its lowest. Most of it comes in the first half of the night. Stages are estimated from heart rate and motion, so treat them as a guide.")
        case "sleep_rem_min":
            return String(localized: "REM sleep is when most dreaming happens, and it matters for memory and mood. It comes in longer stretches towards morning, so a short night cuts it first. Stages are estimated from heart rate and motion, so treat them as a guide.")
        case "sleep_light_min":
            return String(localized: "Light sleep makes up around half of a typical night. It bridges waking and the deeper stages, and still counts towards your rest.")
        case "sleep_need_min":
            return String(localized: "Sleep need is how much sleep Hoop estimates you needed, from your baseline need, the previous day's strain and any sleep debt.")
        case "sleep_debt_min":
            return String(localized: "Sleep debt is the sleep you've missed against your need over recent nights. Short nights add to it and longer ones pay it back.")
        case "hr_zones13_min":
            return String(localized: "Time in heart rate zones 1 to 3: easy to moderate effort, like walking, easy cycling or a relaxed run. Most endurance fitness is built here.")
        case "hr_zones45_min":
            return String(localized: "Time in heart rate zones 4 and 5: hard effort close to your maximum, like intervals or racing. It builds fitness quickly but needs recovery afterwards.")
        case "hr_zones_all_min":
            return String(localized: "The total time your heart rate spent in any training zone during the day, from easy to all-out effort.")
        case "strength_min":
            return String(localized: "Time spent in strength training activities recorded during the day.")
        case "weight":
            return String(localized: "Your weight as recorded in Apple Health, for example by a smart scale. Weigh-ins you log in Hoop appear under Weight instead.")
        case "body_fat":
            return String(localized: "Body fat percentage from Apple Health, usually measured by a smart scale. Scales estimate it from electrical resistance, which shifts with hydration, so compare readings taken at the same time of day.")
        case "lean_mass":
            return String(localized: "Lean body mass is everything that isn't fat: muscle, bone, organs and water. It comes from Apple Health, usually measured by a smart scale.")
        case "bmi":
            return String(localized: "Body mass index is your weight divided by the square of your height. It's a rough screening number and can't tell muscle from fat.")
        case "stress":
            return v.metric?.source == "xiaomi-band"
                ? String(localized: "Stress as your Mi Band measured it, from 0 to 100, based on your heart rate variability. Higher means more stress.")
                : String(localized: "Day stress is a 0–3 read of how stressed your body looked that day, from your resting heart rate and HRV against your own normal. Around 1.5 is typical for you; higher means a raised resting heart rate, a lower HRV, or both.")
        default:
            return String(localized: "This shows \(v.title.lowercased()) over the range you pick above. Compare a reading with your own recent average rather than with anyone else's; a steady change over days says more than a single day.")
        }
    }

    private static func manual(_ kind: HoopManualVital) -> String {
        switch kind {
        case .weight:
            return String(localized: "Your weight as you log it. It's the same list as Fuel's weigh-ins, so both tabs always show the same number. Weigh yourself at the same time of day, ideally in the morning, since weight can swing by a kilo or more with water and food alone.")
        case .bloodPressure:
            return String(localized: "Blood pressure is the force of blood against your artery walls, written as systolic (while your heart beats) over diastolic (between beats), in millimetres of mercury. For readings you can compare, measure seated after five minutes' rest, at the same time of day. Below 120/80 is generally considered normal; readings that stay high are worth discussing with a doctor.")
        case .restingHeartRate:
            return String(localized: "A resting heart rate you measured yourself, for example first thing in the morning before getting up. Your strap measures its own overnight resting heart rate separately, under Recovery.")
        case .bloodGlucose:
            return String(localized: "Blood glucose is the amount of sugar in your blood, from a finger-prick meter or a continuous monitor. It rises after meals and falls with activity, so it helps to take readings at similar times. A typical fasting level is about 70–100 mg/dL (3.9–5.6 mmol/L).")
        case .bodyTemperature:
            return String(localized: "Body temperature from a thermometer, not your strap. Normal is around 36.1–37.2 °C (97–99 °F), a little lower in the morning and higher in the evening. 38 °C (100.4 °F) or above is generally considered a fever.")
        }
    }

    /// The chart colour, following the Hoop rule that colour means something: recovery's own scale, sleep
    /// violet, strain blue, the heart coral; body measurements stay neutral.
    static func tint(_ v: HoopVital, latest: Double?) -> Color {
        if v.key == "recovery" { return latest.map { HoopColor.recovery($0) } ?? HoopColor.recoveryHigh }
        if let kind = v.manual {
            switch kind {
            case .bloodPressure, .restingHeartRate: return HoopColor.heart
            case .weight: return HoopColor.energy   // shared with Fuel
            case .bloodGlucose, .bodyTemperature: return HoopColor.text
            }
        }
        switch v.category {
        case .heart, .recovery: return HoopColor.heart
        case .sleep: return HoopColor.sleep
        case .activity: return HoopColor.strain
        case .body, .logged: return HoopColor.text
        }
    }
}
#endif
