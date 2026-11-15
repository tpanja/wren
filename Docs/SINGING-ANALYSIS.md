# Speech and singing analysis: documentation outline

This is the outline of the technical documentation for how Fonos analyzes the speaking and singing voice. Each section lists what it must cover. Sections are written up as the analysis code lands; anything marked **(validate)** needs measurements on Fonos hardware before the documentation states it as fact.

---

## 1. Overview

- What Fonos measures, and why it uses two kinds of sensor
  - **Microphone:** the sound that reaches a listener (pitch, tone, loudness)
  - **Throat accelerometers:** the vibration of the vocal folds as felt at the skin, plus slow laryngeal movement
- What the analysis produces: per-frame features → per-note measures → per-take metrics → per-session trends
- What it is not: a voice-health or diagnostic tool
- Where each result is used: live screen, feedback card, Progress

## 2. Data collection

### 2.1 Hardware and placement

- Band geometry; microphone at the front of the neck; accelerometers left and right of the thyroid cartilage
- Sensor specs to document: mic type and frequency response; accelerometer range (proposed ±8 g), noise density, bandwidth
- Placement tolerance and its effect on amplitude and symmetry **(validate)**

### 2.2 Sampling and transport

- Rates: mic 16 kHz / 16-bit, accelerometers 4 kHz in the voice band, and a 100 Hz low-frequency channel per accelerometer
- Frame structure: 10 ms frames with a shared timestamp and sequence number
- Compression (µ-law mic), BLE throughput budget, dropped-frame detection and concealment
- Clock drift between band and phone, and how it is corrected

### 2.3 Calibration

- **Fit check:** hum on a comfortable note; contact and symmetry thresholds
- **Noise floor:** 2 s of silence at the start of each session
- **Level reference:** relative dBFS by default; optional calibration against a reference SPL meter **(validate)**
- **Personal baselines:** first five sessions per exercise; how baselines refresh (rolling 30 days, with outliers excluded)

### 2.4 Session protocol

- Exercises and why each exists:

  | Exercise | Measures it exists for |
  |---|---|
  | Siren | Range, register shifts |
  | Five-note scale | Pitch accuracy, onsets |
  | Sustained note | Steadiness, vibrato, breath, tone |
  | Arpeggio | Interval accuracy |
  | Song phrase | Everything, in musical context |
  | Speaking-voice check | Speaking pitch and vibration baseline |

- How targets are chosen from the singer's range
- Reference tones: timing, and whether they are audible during the take
- What the singer is told about posture, hydration, and warming up (non-medical wording)

### 2.5 Signal quality

- Checks: contact per side, clipping, noise floor, mic and accelerometer pitch agreement, dropouts
- How quality is scored (good / fair / low) and which metrics each failure suppresses

## 3. Processing pipeline

### 3.1 Pre-processing

- DC removal; mic high-pass at 60 Hz; accelerometer band-pass 70–1,100 Hz; low-pass under 15 Hz for laryngeal motion
- Axis handling: dominant axis vs vector magnitude, and why
- Framing: 40 ms windows with a 10 ms hop for pitch; 25 ms for spectral features

### 3.2 Voicing detection

- Mic energy above an adaptive noise floor, combined with accelerometer vibration presence
- Why the accelerometer makes voicing robust in noisy rooms (it barely picks up airborne sound) **(validate)**

### 3.3 Pitch tracking

- Algorithm: YIN (cumulative mean normalized difference) with parabolic interpolation and octave-error checks; pYIN-style smoothing over candidates
- Fusion: mic F0 by default; accelerometer F0 when the mic is noisy or clipped; flag frames where they disagree by more than 50 cents
- Conversion to cents relative to the target note; A4 = 440 Hz reference
- Known failure modes: breathy voice, very high soprano notes, fry, and the octave errors each causes

### 3.4 Note segmentation and alignment

- Segmenting voiced regions into notes (pitch plateaus, onsets, offsets)
- Aligning sung notes to the exercise pattern with dynamic time warping over note sequences
- Handling missed, extra, or merged notes

### 3.5 Note-level measures

- **Onset:** settling time and pitch excursion (scoop/overshoot)
- **Sustain:** pitch mean and SD after low-pass below 3 Hz (vibrato removed)
- **Vibrato:** detrended pitch → spectrum in the 3–9 Hz band → rate, extent, regularity; minimum note length 0.6 s
- **Dynamics:** frame levels, sustain level SD, phrase dynamic range
- **Tone:** HNR (autocorrelation method), 2–4 kHz vs 0–2 kHz energy ratio, jitter and shimmer (technical only)

### 3.6 Accelerometer measures

- Voice-band RMS per note and the singer's baseline normalization
- Left/right symmetry
- Vibration-to-sound ratio per note **(validate)**
- Onset type from envelope rise times: accelerometer vs mic, thresholds **(validate)**
- Laryngeal elevation from low-frequency displacement (double integration with drift control) **(validate)**
- Accelerometer F0 for pitch fusion

### 3.7 Take and session aggregation

- From notes to the take: weighting by note duration; outlier handling
- From takes to sessions and trends: per-exercise baselines, 7- and 28-day windows, minimum data before a trend is shown

### 3.8 Performance budget

- On-device budget: live screen at 30 fps, analysis under 10% CPU on an iPhone 12-class device
- Vectorized DSP with Accelerate (vDSP)

## 4. Interpretation

### 4.1 Reference bands

- Pitch: ±25 cents as "in tune" for coaching, and why it is lenient compared with a professional standard (about ±10)
- Vibrato rate and extent norms in classical and contemporary styles, with sources; contemporary styles often use little or no vibrato, so it is never required
- Onset settling and scoop norms **(validate)**

### 4.2 Personal baselines over norms

- Why Fonos compares singers mostly with themselves
- Thresholds for "steady" vs "changed" (for example, a 5% change or one SD of the baseline)

### 4.3 Confidence

- How signal quality, take length, and metric status flow into the feedback's `confidence`
- What the app shows when confidence is low

### 4.4 What not to conclude

- No voice-health or diagnostic claims, even for hoarseness, strain, or asymmetry
- Exploratory accelerometer metrics are observations, never focuses, until validated
- Style matters: a "scoop" can be intentional in pop and jazz

## 5. Speech and singing

- **Speaking-voice check:** habitual speaking F0, speaking F0 range, and speaking throat vibration
- **Comparing speech and singing:**
  - where the singing range sits relative to speaking pitch
  - vibration-to-sound ratio in speech vs singing **(validate)**
  - larynx height when singing high vs the speaking baseline **(validate)**
- **The speak-then-sing drill:** why speaking a line first can help pitch and ease
- Limits: accents, languages, and reading vs spontaneous speech

## 6. From metrics to feedback

- The local rule engine: priority order, thresholds, the drill mapping
- LLM feedback: what is sent, prompt rules, schema, and validation (see [LLM-FEEDBACK.md](LLM-FEEDBACK.md))
- How the two are kept consistent (same schema, same drill library)

## 7. Validation plan

- **Synthetic tests:** tones with known detuning, vibrato, onsets, and noise; pass thresholds for each metric
- **Reference recordings:** consented singers recorded with Fonos and a studio microphone; compare pitch and level
- **Expert agreement:** voice teachers rate takes; correlation with Fonos metrics and focus choices
- **Accelerometer studies:** relate vibration amplitude, symmetry, onset type, and laryngeal motion to teacher ratings
- **Device coverage:** iPhone models, band revisions, rooms
- Success criteria per metric, decided before data collection

## 8. Privacy and data handling

- On-device processing; discard-by-default; opt-in saved takes stored with file protection
- What leaves the phone (rounded metrics only), and when (only with feedback consent)
- Retention, export, deletion
- Research data: separate explicit consent, de-identification, and an ethics review where required

## 9. Limitations

- Accelerometer coupling varies with neck shape, skin, and band tension
- Microphone placement on the neck colors the tone measures
- Pitch tracking in polyphonic backing (backing audio is not mixed into the mic during takes)
- Children's and very high voices: sample rate and placement limits

## 10. Glossary

Cents, F0, onset, sustain, vibrato rate and extent, register, passaggio, HNR, singer's formant, jitter, shimmer, laryngeal elevation, dBFS.

## 11. References to cite

- de Cheveigné, A., & Kawahara, H. (2002). YIN, a fundamental frequency estimator for speech and music. *JASA*, 111(4).
- Mauch, M., & Dixon, S. (2014). pYIN: A fundamental frequency estimator using probabilistic threshold distributions. *ICASSP*.
- Sundberg, J. (1987). *The Science of the Singing Voice*. Northern Illinois University Press.
- Titze, I. R. (1994). *Principles of Voice Production*. Prentice Hall.
- Prame, E. (1994). Measurements of the vibrato rate of ten singers. *JASA*, 96(4).
- Švec, J. G., Titze, I. R., & Popolo, P. S. (2005). Estimation of sound pressure levels of voiced speech from skin vibration of the neck. *JASA*, 117(3).
- Mehta, D. D., et al. (2012). Mobile voice health monitoring using a wearable accelerometer sensor and a smartphone platform. *IEEE Transactions on Biomedical Engineering*, 59(11).

Verify every citation's details against the source before publishing.
