# Fonos

iOS companion app for the Fonos throat band. The band measures throat vibration with one contact microphone and two piezo sensors, one on each side of the larynx. The phone turns dysarthric speech from people living with ALS into clear speech, and turns the same signals into a running record of how their speech is changing.

The person with ALS operates the app themselves, often with declining hand control. Every action is a single large tap, and the Speak button is never more than one tap away.

> **Current phase: toy data only.** There is no Bluetooth connection to the band yet. A simulated band (`ToyBand`) generates speech-shaped signals at the real band's sample rates, and a toy translator returns scripted phrases that are spoken aloud. Every screen that shows numbers labels them as sample data. Fonos is not a medical device and does not diagnose.

## Run it

Requirements: Xcode 15 or later, iOS 17 or later. There are no third-party packages. The two bundled fonts are OFL-licensed assets, not code dependencies.

```bash
open Fonos.xcodeproj
```

Pick an iPhone simulator and press Run. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or moving files, regenerate it:

```bash
xcodegen generate
```

Run the unit tests:

```bash
xcodebuild -project Fonos.xcodeproj -scheme Fonos -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## What's in the app

| Screen | What it does |
|---|---|
| **Speak** | The live throat signal (the Fold view), a 132 pt Speak button, the translated phrase with a replay button and its clarity score, quick-phrase buttons, and phrases said today. |
| **Progress** | Clarity, Strength, and Pace rings for the selected range (week, month, or 3 months), a plain-language insight against the user's own baseline, and a card for each of the six measures. Each card opens a detail chart. |
| **Band** | Band status and battery, a live trace and skin-contact state for each sensor, and the live left/right balance. |
| **Settings** (sliders icon) | Voice and Personal Voice, speaking speed, when listening stops, whether to speak automatically, quick phrases, and appearance (Dark by default, Light, or match iPhone). |

The **Fold view** is the app's signature. The mic waveform runs along a midline, the left piezo's vibration rises above it, and the right piezo's falls below, at one shared scale. Balanced vibration draws a mirror image. A weaker side draws a visibly shorter half.

## The six measures

All six are computed per session from 10 ms frames, using only frames the voicing detector marks as voiced, and shown against the user's baseline (the mean of their first five sessions).

| Measure | From | Definition |
|---|---|---|
| **Strength** | Mic | Mean voiced level in dBFS, shown as % of baseline amplitude |
| **Pace** | Mic | Syllable nuclei per second of voiced time |
| **Pauses** | Mic | Share of the speaking span that is unvoiced |
| **Symmetry** | Both piezos | 1 − \|L − R\| / (L + R) over voiced frames |
| **Pitch variation** | Mic | Mean change between consecutive 20 ms F0 estimates, as % of mean F0 |
| **Clarity** | Translator | Mean translator confidence per phrase (a placeholder until a real translator exists) |

A change under 5% from baseline is reported as steady. The full derivation of every measure, with figures from the app's own analyzer, is in the [methods paper](https://claude.ai/artifact/PhYCk7ncK86W6gCAn5yFjg).

## Design

- **Look.** Dark slate ground with WHOOP-style rings and Apple Health–style summary cards. Each stream keeps one color everywhere: mic amber, left piezo teal, right piezo violet.
- **Type.** Atkinson Hyperlegible Next (Braille Institute) for all reading text, chosen for low-vision legibility. Sora for numerals, titles, and tracked caps. Both are in `Fonos/Resources/Fonts` with their licenses and scale with Dynamic Type.
- **Icons.** A custom SVG set in `Assets.xcassets/Icons` on a 24 pt grid with a 1.8 pt rounded stroke. No SF Symbols.
- **Accessibility.** Targets of 60 pt or larger for primary actions, full VoiceOver labels, Dynamic Type through accessibility sizes (the Speak button moves to the top at the largest sizes), Reduce Motion respected, and no gesture-only or timed actions.
- **Performance.** Live charts pause when off screen, and views copy only the buffers they draw. In a Release build on the simulator, the app uses about 10% of one core on the Speak screen and about 2% on Progress.

## Layout

```
Fonos/
  App/          FonosApp, RootView, FonosEngine (coordinator: streaming, sessions, Speak flow)
  Design/       Theme tokens, Typography, Icons, shared components, FoldView
  Signal/       ToyBand (simulated sensors), StreamStore (display buffers), DSP, SpeechAnalyzer
  Speech/       SpeechTranslator protocol + ToyTranslator, VoiceOutput (Personal Voice aware)
  Data/         SessionRecord, Metric, SessionStore + ToyHistory, Insights (baseline and trends)
  Features/     Speak, Progress, Band, Settings screens
  Resources/    Asset catalog (app icon, custom icons), bundled fonts
FonosTests/     Unit tests: DSP, pitch tracking, syllable detection, analyzer, baseline, trends
Docs/           Data handling, UI design, hardware integration notes
```

## Documentation

- [Methods paper](https://claude.ai/artifact/PhYCk7ncK86W6gCAn5yFjg): how each measure is derived, the synthetic signal model, verification, limitations, and a validation plan.
- [Docs/DATA.md](Docs/DATA.md): the three streams, how toy data is generated, and the data pipeline.
- [Docs/UI-DESIGN.md](Docs/UI-DESIGN.md): design direction, typography, icons, accessibility, and performance.
- [Docs/HARDWARE-INTEGRATION.md](Docs/HARDWARE-INTEGRATION.md): where the real band will plug in (`FrameSource`). The Bluetooth layer is intentionally not built yet.
- [PRODUCT.md](PRODUCT.md): users, purpose, principles, and constraints.

## Known limitations

- No hardware link yet. All signals and history are synthetic.
- Clarity reflects the toy translator, not the user's speech.
- Pace and Pauses count the quiet gaps inside syllables, so their absolute values run higher than published articulation-rate and pause measures. They are meant for tracking change within one person. See the methods paper, Section 14.
- No measure has been validated against clinical scales.
