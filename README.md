<p align="center">
  <img src="docs/assets/zhoop-icon.png" alt="Zhoop" width="96">
</p>

<h1 align="center">Zhoop</h1>

<p align="center"><b>A WHOOP companion for iPhone, built around one goal: losing weight.</b></p>

<p align="center"><sub>A personal fork of <a href="https://github.com/ryanbr/noop">NOOP</a>. Offline, on-device, no account, no cloud.</sub></p>

---

## Why this fork exists

[NOOP](https://github.com/ryanbr/noop) is an excellent open-source, local-first app for WHOOP straps:
it pairs over Bluetooth, keeps everything on your device, and computes recovery, strain, HRV and sleep
itself. It shows a lot.

I forked it to cater to my own fitness needs. I'm on a calorie deficit, working out, and trying to get
from where I am to a goal weight by a date. I wanted the app to answer one question every day: **how
much can I eat today, and am I on track?** So Zhoop strips the app down to that and adds the weight-loss
pieces NOOP doesn't have.

## What's different from NOOP

**Today** is rebuilt around the deficit:

- **Calories left today**: a ring showing your food allowance minus what you've eaten, with your
  workout burn against its target and a protein bar.
- **Calories → fat**: burned − eaten = your deficit, shown as grams of fat (1 kg ≈ 7,700 kcal), with
  a 7-day bar chart.
- **Heart rate, strap battery, calories burned and steps**, straight from the strap.
- **Food log** with calories and optional protein, and one-tap re-adding of recent foods.
- **Goal**: set a goal weight and a date. Zhoop works out the daily deficit, splits it between eating
  less and working out, and re-plans every day. It shows whether you're on track and when you'll
  actually get there at your recent pace.

Built for someone without a scale:

- **Estimated weight**: the app tracks your weight from your logged deficit, day by day, and uses it
  for every calculation. Enter a real weigh-in any time and it restarts from that.
- **Logging buffer**: counts every logged calorie 10% higher (adjustable), because most people
  under-log.

And less of everything else:

- Two tabs: **Today** and a simple **Sleep** tab (last night, the past 7 nights, averages).
- Devices, Apple Health, plan settings and settings live behind the gear on Today.

The Bluetooth, strap protocol, storage, sleep staging and heart-rate calorie model are NOOP's, unchanged.

## Status

This is a personal build for my iPhone and my WHOOP 5.0 / MG. The Mac and Android apps from NOOP are
still in the repository but have not been reworked beyond the name. Everything is an estimate, not medical advice.

## Build and run on an iPhone

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig`, then set your own
   `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM` in it. That file is gitignored.
2. `xcodegen generate`
3. Open `Strand.xcodeproj`, choose the **NOOPiOS** scheme and your iPhone, and run.

Pairing a WHOOP 5.0 / MG needs the strap freed from the official WHOOP app first; see
[docs/IOS.md](docs/IOS.md) and the pairing notes in [NOOP's README](https://github.com/ryanbr/noop#readme).

## Credit

All the hard work under the hood belongs to **NOOP** and its contributors:
[github.com/ryanbr/noop](https://github.com/ryanbr/noop). NOOP in turn builds on
[johnmiddleton12/my-whoop](https://github.com/johnmiddleton12/my-whoop) and
[b-nnett/goose](https://github.com/b-nnett/goose); see [ATTRIBUTION.md](ATTRIBUTION.md) and [NOTICE](NOTICE).

The documents in [`docs/`](docs/), [CHANGELOG.md](CHANGELOG.md) and the contributor guides are NOOP's
own and describe NOOP. They're kept as they are.

## License

Zhoop is a fork of NOOP and stays under NOOP's license,
[PolyForm Noncommercial 1.0.0](LICENSE): free for noncommercial use.

Required Notice: Copyright 2026 NoopApp

Zhoop is not affiliated with, endorsed by, or connected to WHOOP, Inc. or the NOOP project. "WHOOP"
is used only to identify the hardware the app works with.
