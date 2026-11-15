# Fonos

iOS companion app for the Fonos throat band. The band measures throat vibration with one contact microphone and two piezo sensors, one on each side of the larynx. The phone turns dysarthric speech from people living with ALS into clear speech, and turns the same signals into a running record of how their speech is changing.

The person with ALS operates the app themselves, often with declining hand control. Every action is a single large tap, and the Speak button is never more than one tap away.

> **Current phase: real band link, toy translation.** Fonos connects to the ESP32 throat band over Bluetooth LE (firmware in [`firmware/`](firmware/README.md)) and streams its microphone and piezo signals live. Until a band is connected, a simulated band (`ToyBand`) generates speech-shaped signals at the same rates. The translator is still a toy that returns scripted phrases, which are spoken aloud. The session and check histories are synthetic. Every screen that shows numbers labels them as sample data. Fonos is not a medical device and does not diagnose.

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
| **Progress** | Clarity, Strength, and Pace rings for the selected range (week, month, or 3 months), a plain-language insight against the user's own baseline, the weekly Speech check card, a voice-banking prompt once speech starts to change, and all 14 measures grouped by speech system (breathing, voice, articulation, rhythm and intelligibility). Each card opens a detail chart. |
| **Speech check** (Progress → Start check) | A guided weekly check of about 3 minutes: a long “ahh”, “pa-pa-pa”, “pa-ta-ka”, and a read passage. Large Start and Skip buttons, instructions that can be read aloud, auto-stop on silence or time, and a results screen that compares with last week. |
| **Band** | Connecting the band: one Connect action, a four-step setup guide, troubleshooting, and the bands found nearby (Fonos connects on its own when there's only one). Once connected: battery, signal strength, a live trace for each sensor, and the left/right balance. Fonos remembers the band and reconnects whenever it's in range. The simulated band stays available for trying Fonos without hardware. |
| **Clinic summary** (report icon on Progress, or Settings → Care team) | A two-page PDF for the neurologist or speech therapist. Page 1: a summary and every measure grouped by speech system, with baseline, period mean, change, slope per 30 days with a 95% confidence interval, and status. Page 2: a trend chart per measure, data quality (sessions and weekly checks), and methods. Covers everything since the last summary was shared. Optional name and date of birth stay on the phone. Shared through the system share sheet (Mail, Messages, Files, Print). |
| **Settings** (sliders icon) | Voice and Personal Voice, speaking speed, when listening stops, whether to speak automatically, quick phrases, the clinic summary, and appearance (Light by default, Dark, or match iPhone). |

The **Fold view** is the app's signature. The mic waveform runs along a midline, the left piezo's vibration rises above it, and the right piezo's falls below, at one shared scale. Balanced vibration draws a mirror image. A weaker side draws a visibly shorter half.

## Measures

Six measures come from everyday conversation. They are computed per session from 10 ms frames, using only frames the voicing detector marks as voiced, and shown against the user's baseline (the mean of their first five sessions).

| Measure | From | Definition |
|---|---|---|
| **Strength** | Mic | Mean voiced level in dBFS, shown as % of baseline amplitude |
| **Pace** | Mic | Syllable nuclei per second of voiced time |
| **Pauses** | Mic | Share of the speaking span that is unvoiced |
| **Symmetry** | Both piezos | 1 − \|L − R\| / (L + R) over voiced frames |
| **Pitch variation** | Mic | Mean change between consecutive 20 ms F0 estimates, as % of mean F0 |
| **Clarity** | Translator | Mean translator confidence per phrase (a placeholder until a real translator exists) |

Eight more come from the **weekly Speech check**, whose fixed tasks make results comparable week to week. Their baseline is the mean of the first three checks.

| Measure | Task | Definition |
|---|---|---|
| **Longest “ahh”** (MPT) | Sustained /a/ | Longest continuous voicing, gaps under 150 ms bridged |
| **Voice clarity** (HNR) | Sustained /a/ | Harmonics-to-noise ratio from autocorrelation of the steady middle |
| **“pa-pa-pa” speed** (AMR) | /pa/ for 6 s | Syllables per second |
| **“pa-ta-ka” speed** (SMR) | /pataka/ for 6 s | Syllables per second |
| **“pa-ta-ka” timing variation** | /pataka/ for 6 s | Coefficient of variation of syllable intervals, sub-frame peak timing |
| **Reading rate** | Fixed passage | Syllables per second of speaking time, only pauses of 250 ms or more removed |
| **Syllables per breath** | Fixed passage | Syllables ÷ (pauses of 250 ms or more + 1) |
| **Reading stamina** | Fixed passage | Voiced level, last third minus first third, dB |

A change under 5% from baseline is reported as steady. Reading stamina sits near zero, so it is compared by absolute difference instead (1 dB). The full derivation of every measure, with figures from the app's own analyzer, is in the [methods paper](https://claude.ai/artifact/PhYCk7ncK86W6gCAn5yFjg).

## Design

- **Look.** Light by default, with colors sampled from the band itself: white-shell cards on a pale grey ground, black-strap text, WHOOP-style rings, and Apple Health–style summary cards. Each stream keeps one color everywhere: mic grey-green (the liner), left piezo green and right piezo blue (the sensor wires).
- **Type.** Atkinson Hyperlegible Next (Braille Institute) for all reading text, chosen for low-vision legibility. Sora for numerals, titles, and tracked caps. Both are in `Fonos/Resources/Fonts` with their licenses and scale with Dynamic Type.
- **Icons.** A custom SVG set in `Assets.xcassets/Icons` on a 24 pt grid with a 1.8 pt rounded stroke. No SF Symbols.
- **Accessibility.** Targets of 60 pt or larger for primary actions, full VoiceOver labels, Dynamic Type through accessibility sizes (the Speak button moves to the top at the largest sizes), Reduce Motion respected, and no gesture-only or timed actions.
- **Design review skill.** The repo carries the [unslop-ui](.claude/skills/unslop-ui/SKILL.md) Claude skill (vendored unchanged from [vibecoded-design-tells](https://github.com/JCarterJohnson/vibecoded-design-tells), MIT). Claude Code loads it automatically in this repo when you ask it to build, restyle, or review UI, and uses it to avoid default "AI-made" looks. Its scanner (`python3 .claude/skills/unslop-ui/scripts/devibe_scan.py <path>`) reads web files only (HTML, CSS, JS/TS, and similar), so it finds nothing in the Swift sources; for this app, audit by eye against [references/tells.md](.claude/skills/unslop-ui/references/tells.md).
- **Performance.** Live charts pause when off screen, and views copy only the buffers they draw. In a Release build on the simulator, the app uses about 10% of one core on the Speak screen and about 2% on Progress.

## Layout

```
Fonos/
  App/          FonosApp, RootView, FonosEngine (coordinator: streaming, sessions, Speak flow)
  Design/       Theme tokens, Typography, Icons, shared components, FoldView
  Signal/       BandProtocol (BLE wire format), BluetoothBand (real band), ToyBand (simulated), StreamStore, DSP, SpeechAnalyzer
  Speech/       SpeechTranslator protocol + ToyTranslator, VoiceOutput (Personal Voice aware)
  Check/        Speech check tasks, TaskAnalysis (MPT, HNR, DDK, reading), check records + ToyCheckHistory, CheckStore
  Data/         SessionRecord, Metric, Measure (all measures, grouped by SpeechSystem), SessionStore + ToyHistory, Insights
  Report/       ClinicReport (period, slopes, status, data quality), ClinicReportPage (the two PDF pages), ReportRenderer
  Features/     Speak, Progress, Speech check, Band, Settings, and Clinic summary screens
  Resources/    Asset catalog (app icon, custom icons), bundled fonts
.claude/skills/ unslop-ui design-review skill for Claude Code (not part of the app build)
FonosTests/     Unit tests: DSP, pitch tracking, syllable detection, analyzer, baseline, trends, task analysis, report statistics and PDF
Docs/           Data handling, UI design, hardware integration notes
firmware/       ESP32 band firmware (Arduino) and its flashing and wiring guide
```

## Documentation

- [Methods paper](https://claude.ai/artifact/PhYCk7ncK86W6gCAn5yFjg): how each measure is derived, the synthetic signal model, verification, limitations, and a validation plan.
- [Docs/DATA.md](Docs/DATA.md): the three streams, how toy data is generated, and the data pipeline.
- [Docs/UI-DESIGN.md](Docs/UI-DESIGN.md): design direction, typography, icons, accessibility, and performance.
- [Docs/HARDWARE-INTEGRATION.md](Docs/HARDWARE-INTEGRATION.md): how the band connects (`BluetoothBand` behind `FrameSource`), reconnection, lost frames, and what's left.
- [firmware/README.md](firmware/README.md): flashing the ESP32, wiring, gains, and the Bluetooth protocol.
- [PRODUCT.md](PRODUCT.md): users, purpose, principles, and constraints.

## Known limitations

- The Bluetooth link and firmware are untested on hardware so far: the protocol is covered by unit tests, but nothing has been run against a real board (the iOS Simulator has no Bluetooth).
- The band doesn't sense skin contact or measure its battery unless wired for it, so the app shows those as not reported.
- The translator is still the toy: with the real band, Fonos speaks scripted phrases, not your words. Session and check histories are synthetic.
- Clarity reflects the toy translator, not the user's speech.
- Pace and Pauses count the quiet gaps inside syllables, so their absolute values run higher than published articulation-rate and pause measures. They are meant for tracking change within one person. See the methods paper, Section 14. The check's reading rate removes only pauses of 250 ms or more, which avoids this for the passage.
- Check results come from the simulated band performing each task, tuned to land near the end of the sample history. Real task recordings and their analysis on dysarthric speech are untested.
- Checks and sessions are kept in memory only, so a check saved in the app is gone after a relaunch.
- No measure has been validated against clinical scales.
