# Fonos singing coach: app specification

Status: draft for approval. The iOS code still contains the earlier prototype; the [migration plan](#9-migration-plan-from-the-current-prototype) lists what changes once this spec is approved.

Related documents:

- [SINGING-ANALYSIS.md](SINGING-ANALYSIS.md): how the analysis works (outline)
- [LLM-FEEDBACK.md](LLM-FEEDBACK.md): feedback server, prompt, schema, and sample output
- [UI-REDESIGN.md](UI-REDESIGN.md): screen-by-screen mock-up descriptions
- [HARDWARE-INTEGRATION.md](HARDWARE-INTEGRATION.md): what the band must provide

---

## 1. Goal

- Fonos is a **singing coach**. It listens to the voice through a microphone and feels it through two throat accelerometers, then tells the singer the one thing to work on next.
- After every take, the singer gets:
  - a short headline and summary
  - up to two things that went well
  - **one focus** with a drill they can do right away
- Over weeks, the singer sees pitch accuracy, steadiness, and range improve against their own baseline.

## 2. Users and modes

| | Beginner (default) | Technical detail (setting) |
|---|---|---|
| Who | Hobbyists learning on their own | Voice students practicing between lessons |
| Language | Plain words: "a little flat", "wobbly", "breathy start" | Cents, onset type, passaggio, singer's formant, HNR |
| Numbers shown | Rings and one value per card | Full values, ranges, per-note tables |
| Feedback length | Two sentences and one drill | Adds a technical note |

- One switch in Settings: **Coaching level: Beginner / Technical detail**.
- Optional profile: voice type (soprano, mezzo, alto, tenor, baritone, bass, "not sure"), goals (in tune, stronger, wider range, steadier, vibrato, "just for fun").

## 3. Sensors and data

| Stream | Sensor | Placement | Proposed rate | What it gives |
|---|---|---|---|---|
| Mic | Contact or close microphone on the band | Front of the neck | 16 kHz, 16-bit (µ-law over BLE) | Sound: pitch, tone, loudness, vibrato |
| Left accel | 3-axis accelerometer | Left of the larynx | 4 kHz, dominant axis or vector magnitude | Skin vibration, laryngeal motion |
| Right accel | 3-axis accelerometer | Right of the larynx | 4 kHz | Same, right side |

- Accelerometers at 4 kHz cover fundamentals up to about 1.1 kHz (a soprano's high C6 is 1,047 Hz).
- Each accelerometer's low-frequency band (below 15 Hz) is kept separately, at 100 Hz, for **laryngeal motion** (how much the larynx rises).
- The band timestamps all three streams in 10 ms frames so they stay aligned.
- On the phone, the iPhone microphone can optionally record room sound for reference. It is off by default.

## 4. Core flows

1. **Fit check** (first run, and whenever signal quality drops). Hum a comfortable note. Fonos checks that both accelerometers feel vibration and that left and right are within 20% of each other, then shows how to adjust the band.
2. **Range finder** (first run, then monthly). Glide low to high and high to low. Fonos records the lowest and highest notes held in tune for at least half a second.
3. **Practice session**
   - Pick an exercise: Siren, Five-note scale, Sustained note, Arpeggio, Song phrase, or Speaking-voice check.
   - The exercise is pitched to the singer's range and played as a reference tone, or skipped.
   - Sing a take while the live screen shows the target note, the tuning needle, the pitch lane, and the throat strip.
   - The take ends on tap or after 2 s of silence.
   - The feedback card appears: rule-based immediately, then refined by the LLM within about 3 s.
   - Then: Try again, Next exercise, or Done.
4. **Speaking-voice check**. Read one short sentence. Fonos measures speaking pitch and throat vibration so it can compare how the singer speaks with how they sing (see [SINGING-ANALYSIS.md](SINGING-ANALYSIS.md) § 5).
5. **Progress review**. Rings for the chosen range, a weekly insight, all measures, vocal range over time, and practice days.

## 5. Metrics

Every metric has a beginner name, a technical name, a source, and a validation status:

- **Established**: widely used in voice science.
- **Exploratory**: plausible, but must be validated with Fonos hardware before the app coaches on it. The app labels exploratory metrics and never makes them the focus of feedback until they are validated.

### 5.1 Pitch (microphone, cross-checked against accelerometer F0)

| Beginner name | Technical name | Definition | Unit / display | Status |
|---|---|---|---|---|
| **In tune** | Pitch accuracy | Share of voiced time within ±25 cents of the target note, after onset settling | % (ring) | Established |
| How far off | Mean pitch error | Mean signed deviation from target; sign shows flat or sharp | cents | Established |
| **Steady notes** | Sustain stability | Standard deviation of pitch on held notes after removing vibrato (low-pass below 3 Hz) | cents | Established |
| Landing the note | Onset settling time | Time from voicing onset until pitch stays within ±25 cents for 100 ms | ms | Established |
| Scoops and overshoots | Onset pitch excursion | Largest deviation in the first 150 ms; scoop if below the target, overshoot if above | cents | Established |
| **Range** | Comfortable range | Lowest to highest note held in tune for at least 0.5 s across sessions | note names, semitones | Established |

### 5.2 Vibrato (microphone)

| Beginner name | Technical name | Definition | Unit | Status |
|---|---|---|---|---|
| Vibrato speed | Vibrato rate | Dominant frequency of pitch oscillation, 3–9 Hz band, on notes held at least 0.6 s | Hz (typical classical singing is about 5–7) | Established |
| Vibrato width | Vibrato extent | Half the peak-to-peak pitch oscillation | ± cents | Established |
| Even vibrato | Vibrato regularity | Coefficient of variation of rate and extent across cycles | % | Established |

### 5.3 Loudness and breath (microphone)

| Beginner name | Technical name | Definition | Unit | Status |
|---|---|---|---|---|
| Volume control | Dynamic range | Difference between the 95th and 5th percentile level on voiced frames | dB | Established |
| Steady volume | Sustain level stability | Level standard deviation on held notes | dB | Established |
| Breath length | Phrase duration | Longest continuous voiced phrase; for the Sustained note exercise, maximum phonation time | s | Established |

### 5.4 Tone (microphone)

| Beginner name | Technical name | Definition | Unit | Status |
|---|---|---|---|---|
| Clear vs breathy | Harmonics-to-noise ratio (HNR) | Periodic-to-aperiodic energy ratio on held notes | dB | Established |
| Ring | Singer's formant energy | Energy at 2–4 kHz relative to 0–2 kHz | dB | Established (needs the 16 kHz mic) |
| Roughness | Jitter / shimmer | Cycle-to-cycle variation in period and amplitude | % | Established; shown in Technical only |

### 5.5 Throat vibration (accelerometers)

| Beginner name | Technical name | Definition | Unit | Status |
|---|---|---|---|---|
| **Throat vibration** | Neck surface vibration amplitude | RMS acceleration in the voice band (70–1,100 Hz), per note, normalized to the singer's baseline | % of baseline | Established as a measure; coaching meaning exploratory |
| Even both sides | Left/right vibration symmetry | `1 − abs(L − R) / (L + R)` on voiced frames | % (100 = equal) | Exploratory; mostly a fit check |
| Effort for the sound | Vibration-to-sound ratio | Accelerometer amplitude relative to mic level, per note, against baseline. Rising means more throat vibration for the same loudness. | ratio vs baseline | Exploratory |
| Easy or hard start | Onset type | Rise time of the accelerometer envelope versus the mic envelope: abrupt (hard, glottal), simultaneous (balanced), or sound-after-air (breathy) | label | Exploratory |
| Larynx rising | Laryngeal elevation | Low-frequency (<15 Hz) displacement from the accelerometers during a phrase, relative to the singer's speaking baseline | relative units | Exploratory |
| (none) | Accelerometer F0 | Pitch from the accelerometers; used to keep pitch tracking reliable in noise and to detect mic dropouts | Hz | Established |

### 5.6 Practice

| Metric | Definition |
|---|---|
| Practice minutes | Voiced time plus exercise time, per day |
| Days practiced | Days with at least one completed take (the WHOOP-style weekday row) |
| Takes | Completed takes per exercise |

### 5.7 Signal quality (always computed, drives honesty)

- Accelerometer contact on each side (vibration present when the mic hears voicing)
- Mic clipping (more than 0.1% of samples at full scale)
- Room noise floor (dBFS during silence)
- Mic and accelerometer pitch agreement (share of frames within 50 cents)
- Dropped BLE frames

When quality is low, the feedback says so and does not coach on the affected metrics.

### 5.8 Headline rings

| Ring | Metric | Fill |
|---|---|---|
| **In tune** | Pitch accuracy | % directly |
| **Steady** | Sustain stability | 100% at ≤5 cents SD, 0% at ≥40 cents |
| **Range** | Comfortable range | Semitones ÷ 24 (two octaves fills the ring) |

Each ring shows its unit inside it: %, %, and semitones.

## 6. LLM feedback

Summary (full detail in [LLM-FEEDBACK.md](LLM-FEEDBACK.md)):

- **Path:** iPhone → HTTPS → Fonos feedback server → Claude Messages API. The API key lives only on the server.
- **Model:** `claude-opus-5-5` at `effort: "low"` (short, fast feedback). Server-side refusal fallback is on (`fallbacks: "default"`).
- **Input:** a JSON payload of computed metrics, the singer's baseline and trends, signal quality, exercise context, and coaching level. Never audio, vibration samples, or free-form personal data.
- **Output:** structured JSON enforced with `output_config.format`, rendered as the feedback card.
- **Caching:** the fixed system prompt (role, rules, metric glossary, drill library) is cached; per-take metrics come after it.
- **Guardrails:** cite only provided numbers; one focus per take; never diagnose; say so when signal quality is low; tone follows the coaching level.
- **Fallback:** a local rule engine produces the same JSON shape immediately and whenever the server is unavailable or feedback is off. The LLM version replaces it when it arrives.

## 7. Privacy by design

- **On-device analysis.** Audio and vibration are analyzed in memory on the phone. Raw signals never leave the device.
- **Nothing kept by default.** Raw signals are discarded after analysis. "Save this take" is an explicit, per-take choice, stored only on the device with complete file protection.
- **Minimum data to the server.** Only rounded metrics, exercise type, coaching level, and trends are sent. No names, contacts, location, device identifiers, or audio. The singer's typed goals are optional and sent only if they turn on "Use my goals in feedback".
- **Consent first.** LLM feedback is off until the singer reads a one-screen explainer ("What leaves your phone") and turns it on. The local coach works without it.
- **No account.** A random install ID, rotated on reset, is used only to rate-limit the server.
- **Server.** It is stateless: it doesn't store payloads, and it logs only status codes and timings. It authenticates the app with App Attest and enforces rate limits. Use the strictest data-retention arrangement available on the API account; check zero-data-retention eligibility for the chosen model before launch.
- **User control.** Export everything as CSV/JSON; delete everything in one tap. Turning feedback off stops all network calls.
- **Permissions.** Microphone access is requested only when the singer first records with the iPhone mic. The band link will need Bluetooth permission.
- **Not health data.** Singing metrics are not written to HealthKit.

## 8. Out of scope (this version)

- Dysarthric-speech translation (removed entirely)
- Diagnosing voice disorders or vocal health
- Song karaoke with licensed backing tracks (no licensed catalog yet)
- Teacher accounts and sharing
- Real-time LLM coaching during a take (feedback comes after each take)

## 9. Migration plan from the current prototype

The current Swift code is the earlier translator prototype. Once this spec is approved:

| Area | Change |
|---|---|
| `Signal/ToyBand.swift` | Toy band emits 16 kHz mic and two 4 kHz accelerometer streams plus low-frequency motion. The toy singer sings exercises with controllable pitch error, vibrato, and onsets. |
| `Signal/SpeechAnalyzer.swift` | Replace with `SingingAnalyzer`: note segmentation, pitch vs target, vibrato, onsets, dynamics, tone, accelerometer features, signal quality. |
| `Signal/DSP.swift` | Add YIN-style pitch with octave checks, band-pass filters, HNR, and vibrato spectral analysis (Accelerate/vDSP). |
| `Speech/` | Remove `SpeechTranslator`, `ToyTranslator`, `VoiceOutput`. Add `Coach/FeedbackClient.swift` (server call), `Coach/LocalCoach.swift` (rule engine), `Coach/Feedback.swift` (shared JSON model). |
| `Data/` | New `TakeRecord`, `SessionRecord`, singing `Metric` set, baselines per exercise, range history, toy history. |
| `Features/` | Speak → **Sing** (home + live exercise + feedback); Progress keeps its structure with new rings; Band shows accelerometers; Settings adds coaching level, voice type, and feedback consent. |
| Tests | Pitch accuracy against synthetic tones with known detuning, vibrato rate/extent against synthetic vibrato, onset classification on synthetic envelopes, JSON schema round-trip. |

Finish-review findings on the prototype carry into the rebuild:

- State colors (listening, speaking, trend direction) get their own tokens and never borrow metric or stream hues.
- Every ring shows its unit.
- No tracked-caps label stacked above a number; the caption goes after the value.
- Trend charts use monotone or linear interpolation and mark the data points.
- The live chart's in-plot labels move to a gutter or rely on the legend.

## 10. Open decisions

- Final band sample rates and BLE packet layout (depends on firmware throughput)
- Feedback server hosting and region
- Whether to offer reference-tone playback through AirPods while singing (latency)
- Song phrases: user-entered melodies only, or a small licensed set
