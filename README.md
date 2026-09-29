<p align="center">
  <img src="docs/assets/hoop-icon.png" alt="Hoop" width="96">
</p>

<h1 align="center">Hoop</h1>

<p align="center"><b>A free, offline companion for WHOOP straps on iPhone.</b></p>

<p align="center"><sub>A fork of <a href="https://github.com/hackyguru/zhoop">Zhoop</a>, which is a fork of <a href="https://github.com/ryanbr/noop">NOOP</a>. On-device, no account, no cloud.</sub></p>

---

## What it is

Hoop pairs with a WHOOP 4.0 or 5.0 / MG over Bluetooth, keeps everything on your iPhone, and computes
recovery, strain, heart rate variability and sleep itself. There is no Hoop account and no Hoop server.

- **Today**: recovery, strain and sleep at a glance, live heart rate, overnight vitals with their
  week trend, calories and steps.
- **Sleep**: last night's duration against your need, a stage chart, the stage split, and the last
  seven nights.
- **Fuel**: an optional weight goal. A daily food allowance that adapts to your workouts, a food log,
  calories turned into grams of fat, and whether you are on pace (from Zhoop).
- **You**: your strap, profile and preferences, Apple Health, the smart alarm, and data tools.

First run walks through freeing the strap from the official WHOOP app and pairing it.

WHOOP 4.0 has the fullest support. On WHOOP 5.0 / MG, live heart rate works well, while sleep and
recovery are still improving (see NOOP's notes on the 5.0 / MG protocol).

## Try it

Hoop is distributed as a free TestFlight beta: <https://testflight.apple.com/join/ETwKbz1r>

## Build and run on an iPhone

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

1. `cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig`, then set your own
   `BUNDLE_ID_PREFIX` and `DEVELOPMENT_TEAM` in it. That file is gitignored.
2. `xcodegen generate`
3. Open `Strand.xcodeproj`, choose the **NOOPiOS** scheme and your iPhone, and run.

Keep DerivedData outside iCloud-synced folders (the default `~/Library/Developer/Xcode/DerivedData`
is fine): files in a synced Documents folder pick up extended attributes that code signing rejects.

For screenshots in the simulator, a Debug build accepts `--demo-seed` (synthetic sample data) and
`--hoop-tab sleep|fuel|you`.

The Hoop interface lives in [`StrandiOS/Hoop/`](StrandiOS/Hoop/). The Bluetooth, strap protocol,
storage, sleep staging and scoring underneath are NOOP's, unchanged.

## Credit

All the hard work under the hood belongs to **NOOP** and its contributors:
[github.com/ryanbr/noop](https://github.com/ryanbr/noop). Hoop's Fuel tab comes from
[Zhoop](https://github.com/hackyguru/zhoop). NOOP in turn builds on
[johnmiddleton12/my-whoop](https://github.com/johnmiddleton12/my-whoop) and
[b-nnett/goose](https://github.com/b-nnett/goose); see [ATTRIBUTION.md](ATTRIBUTION.md) and
[NOTICE](NOTICE).

The documents in [`docs/`](docs/), [CHANGELOG.md](CHANGELOG.md) and the contributor guides are NOOP's
own and describe NOOP. They're kept as they are.

## License

Hoop is a fork of NOOP and stays under NOOP's license,
[PolyForm Noncommercial 1.0.0](LICENSE): free for noncommercial use.

Required Notice: Copyright 2026 NoopApp

Hoop is not affiliated with, endorsed by, or connected to WHOOP, Inc. or the NOOP project. "WHOOP"
is used only to identify the hardware the app works with. Hoop is not a medical device; every number
is an estimate.
