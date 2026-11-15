# Fonos

iOS companion app for the Fonos throat band. The band will measure throat vibration with one contact microphone and two piezo sensors, and the phone will turn dysarthric speech from people living with ALS into clear speech.

**Current phase: toy data only.** There is no Bluetooth connection yet. A simulated band generates speech-shaped signals at the real band's sample rates, and a toy translator returns scripted phrases that are spoken aloud. This shows how the app will look and behave in real use before the hardware link exists. Every screen that shows numbers says it is sample data.

## Run it

Requirements: Xcode 15 or later, iOS 17 or later. No third-party packages.

```bash
open Fonos.xcodeproj
```

Pick an iPhone simulator and press Run. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or moving files, regenerate it:

```bash
xcodegen generate
```

Run the unit tests (signal processing, metrics, insights):

```bash
xcodebuild -project Fonos.xcodeproj -scheme Fonos -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## What's in the app

| Tab | What it does |
|---|---|
| **Speak** | Live throat signal (the Fold view), a 132 pt Speak button, the translated phrase with replay, and large quick-phrase buttons. |
| **Progress** | Three headline rings (Clarity, Strength, Pace), a plain-language insight against the patient's own baseline, and Apple Health–style cards for all six measures, each with a detail chart. |
| **Band** | Simulated band status, each sensor's live trace and contact state, and the left/right balance. |
| **Settings** (person icon) | Voice and Personal Voice, speaking speed, listening behavior, quick phrases, appearance. |

## Layout

```
Fonos/
  App/          FonosApp, RootView, FonosEngine (coordinator)
  Design/       Theme tokens, shared components, FoldView
  Signal/       ToyBand (simulated sensors), StreamStore, DSP, SpeechAnalyzer
  Speech/       SpeechTranslator protocol + ToyTranslator, VoiceOutput
  Data/         SessionRecord, Metric, SessionStore + ToyHistory, Insights
  Features/     Speak, Progress, Band, Settings screens
FonosTests/     Unit tests
Docs/           Data handling, UI design, hardware integration notes
```

## Documentation

- [Docs/DATA.md](Docs/DATA.md): the three streams, how toy data is generated, and how each measure is computed.
- [Docs/UI-DESIGN.md](Docs/UI-DESIGN.md): design direction, accessibility decisions, and screen anatomy.
- [Docs/HARDWARE-INTEGRATION.md](Docs/HARDWARE-INTEGRATION.md): where the real band will plug in. The Bluetooth layer is intentionally not built yet.
- [PRODUCT.md](PRODUCT.md) and [DESIGN.md](DESIGN.md): product context and the design system.

Fonos is not a medical device and does not diagnose.
