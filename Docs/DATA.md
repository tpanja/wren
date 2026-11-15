# Data handling

Everything in the app today comes from toy data. This document describes the data the app is built around, how the toy data imitates it, and how each measure is computed, so the real band can drop in later without changing the analysis or the UI.

## The three streams

| Stream | Sensor | Rate | Per 10 ms frame | Color |
|---|---|---|---|---|
| Mic | Contact microphone on the throat | 8 kHz | 80 samples | Amber |
| Left | Piezo on the patient's left side of the larynx | 1 kHz | 10 samples | Teal |
| Right | Piezo on the patient's right side | 1 kHz | 10 samples | Violet |

Samples are floats normalized to −1…1. One `SensorFrame` holds 10 ms of all three, time-aligned. Frames arrive on a background queue at about 100 per second.

## Toy data

### Live signal: `ToyBand`

`Fonos/Signal/ToyBand.swift` generates frames on a 10 ms timer:

- **Utterances.** It alternates speaking (1.4–3.2 s) and silence (0.7–1.6 s), so the Fold view shows realistic bursts and gaps.
- **Syllables.** A raised-cosine envelope at 2.9–3.8 syllables per second, with a short gap between syllables.
- **Voice.** A 108–132 Hz fundamental with six harmonics and about 1.2% cycle-to-cycle pitch jitter, plus a low noise floor.
- **Piezos.** The fundamental under the same envelope. The right side is scaled to 0.86 of the left, so the symmetry measure and the Fold view show a mild, realistic imbalance.
- **Status.** Battery starts at 82% and drops slowly while streaming. Both sensors report good contact.

While the Speak button is listening, `ToyBand.setTalking(true)` keeps the toy wearer voicing, so the signal responds to the button the way a real conversation would.

### History: `ToyHistory`

`Fonos/Data/SessionStore.swift` seeds 12 weeks of sessions (one or two most days, a few gap days) from a fixed random seed, so the Progress screen looks the same on every launch. Over the window the trends drift gently the way progressive dysarthria might: pace and strength go down, pauses and pitch variation go up, symmetry and clarity drop a little. These numbers are illustrative only and come from no patient.

### Translation: `ToyTranslator`

`Fonos/Speech/SpeechTranslator.swift` reveals a scripted phrase about two words per second while listening, then returns it with a confidence of 0.74–0.90. `VoiceOutput` speaks it with `AVSpeechSynthesizer`, using the patient's Personal Voice when they have one and allow it.

## Pipeline

```
ToyBand ──frame──▶ StreamStore     (display ring buffers, lock-protected)
            │
            ├────▶ SpeechAnalyzer  (per-session measures)
            │
            └────▶ SpeechTranslator (only while listening)
                        │
                        ▼
                   VoiceOutput (speaks the result)
```

`FonosEngine` owns the pipeline. Display views read `StreamStore.snapshot()` at 30 fps (10 fps with Reduce Motion), so frame-rate data never goes through SwiftUI's observation system.

A **session** runs from when the app becomes active to when it goes to the background. When it ends, `SpeechAnalyzer.summary` produces a `SessionRecord` if there were at least half a second of voiced frames. Raw signals are never stored; only the summary is kept, in memory.

## Measures

All measures are descriptive. They are shown against the patient's own **baseline**, which is the mean of their first five sessions (at least three are needed).

| Measure | Source | How it's computed | Shown as |
|---|---|---|---|
| **Clarity** | Translator | Mean confidence of translated phrases | % |
| **Strength** | Mic | Mean dBFS of voiced frames | % of baseline amplitude, `100 × 10^((dB − baseline dB) / 20)` |
| **Pace** | Mic envelope | Syllable peaks (≥ 4 dB prominence, ≥ 100 ms apart) per second of voiced time | syllables / s |
| **Symmetry** | Left + right piezo | `1 − abs(L − R) / (L + R)` over voiced frames, using per-frame RMS | % (100 = equal) |
| **Pitch variation** | Mic | Mean frame-to-frame change in F0 as a % of mean F0. F0 comes from normalized autocorrelation on a 30 ms window, 70–400 Hz. Jumps across pauses are ignored. | % (lower is steadier) |
| **Pauses** | Mic | Share of frames between the first and last voiced frame that are silent | % |

**Voicing.** A frame counts as voiced when its level is more than 12 dB above an adaptive noise floor. The floor follows quiet frames down immediately and rises slowly (0.02 dB per frame), so it tracks a changing environment without treating speech as noise.

**Trend wording** (`Insights.swift`). A change under 5% from baseline is called "steady". The Progress headline picks the largest change in the worse direction and explains it in plain language, without diagnosing.

## Privacy

Nothing leaves the device. There is no network code, analytics, or account. Session summaries live only in memory for now; when real data arrives, they should be stored with file protection and the patient should control any sharing with clinicians.
