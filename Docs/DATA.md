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

`Wren/Signal/ToyBand.swift` generates frames on a 10 ms timer:

- **Utterances.** It alternates speaking (1.4–3.2 s) and silence (0.7–1.6 s), so the Fold view shows realistic bursts and gaps.
- **Syllables.** A raised-cosine envelope at 2.9–3.8 syllables per second, with a short gap between syllables.
- **Voice.** A 108–132 Hz fundamental with six harmonics and about 1.2% cycle-to-cycle pitch jitter, plus a low noise floor.
- **Piezos.** The fundamental under the same envelope. The right side is scaled to 0.86 of the left, so the symmetry measure and the Fold view show a mild, realistic imbalance.
- **Status.** Battery starts at 82% and drops slowly while streaming. Both sensors report good contact.

While the Speak button is listening, `ToyBand.setTalking(true)` keeps the toy wearer voicing, so the signal responds to the button the way a real conversation would.

### History: `ToyHistory`

`Wren/Data/SessionStore.swift` seeds 12 weeks of sessions (one or two most days, a few gap days) from a fixed random seed, so the Progress screen looks the same on every launch. Over the window the trends drift gently the way progressive dysarthria might: pace and strength go down, pauses and pitch variation go up, symmetry and clarity drop a little. These numbers are illustrative only and come from no patient.

**Speech check tasks.** `ToyBand.setMode` switches the toy wearer to a task: a held vowel of 11–13 s with breath noise (harmonics-to-noise ratio near 14.5 dB), “pa-pa-pa” at 5.3 and “pa-ta-ka” at 4.4 syllables per second with timing jitter, or the reading passage at 3.4–3.7 syllables per second in breath groups of about 7 syllables, about 40% weaker by the end. These are tuned so a live check lands near the end of the sample check history (`TaskAnalysisTests.testToyBandTasksMatchRecentSampleHistory`). `ToyBand.render(_:seconds:)` produces the same frames synchronously for tests.

### Check history: `ToyCheckHistory`

`Wren/Check/SpeechCheckRecord.swift` seeds 13 weekly checks, the last one a week ago so a new check is due. Every task measure drifts slowly in the direction ALS speech changes. Labeled as sample data wherever shown.

### Translation: `ToyTranslator`

`Wren/Speech/SpeechTranslator.swift` reveals a scripted phrase about two words per second while listening, then returns it with a confidence of 0.74–0.90. `VoiceOutput` speaks it with `AVSpeechSynthesizer`, using the patient's Personal Voice when they have one and allow it.

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

`WrenEngine` owns the pipeline. Display views read `StreamStore.snapshot()` at 30 fps (10 fps with Reduce Motion), so frame-rate data never goes through SwiftUI's observation system.

During a Speech check task, frames are also copied into a task buffer and kept out of `SpeechAnalyzer`, so task speech doesn't mix into conversation measures. When the task stops (Done, silence after voicing, or its time limit), `TaskAnalysis` measures the buffer and the buffer is dropped.

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

**Weekly check measures** (`TaskAnalysis.swift`). Each task's voicing threshold is 12 dB above the 10th percentile of that task's own frame levels. Syllable peaks need 4 dB prominence; DDK peaks are at least 80 ms apart and refined to a fraction of a frame by a parabola, since a whole 10 ms frame is about 6% of a DDK interval. Baseline is the mean of the first three checks. See the README for the list.

**Trend wording** (`Measure.swift`, `MeasureTrend`). A change under 5% from baseline is called "steady"; reading stamina uses an absolute band of 1 dB. The Progress headline picks the largest change in the worse direction across all measures, scaling absolute changes so they rank alongside relative ones, and explains it in plain language, without diagnosing.

## Privacy

Nothing leaves the device. There is no network code, analytics, or account. Session summaries live only in memory for now; when real data arrives, they should be stored with file protection and the patient should control any sharing with clinicians.
