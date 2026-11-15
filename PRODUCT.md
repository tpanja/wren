# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Delegated: native SwiftUI app, iOS 17+, Swift 5.9+, no third-party packages. Frameworks used are Apple-only (SwiftUI, Charts, AVFoundation). Project generated with XcodeGen (`project.yml`) and the generated `.xcodeproj` is committed so it opens directly in Xcode.

## Users

The person living with ALS who wears the Fonos throat band. They hold and operate the phone themselves, typically with dysarthric speech and declining hand and arm function that worsens over months. They use it at home and out in the world to be understood by others, and to watch how their speech is changing.

## Product Purpose

Fonos turns throat vibration into clear speech. The band captures three streams (one contact microphone, two piezo vibration sensors on either side of the larynx) and streams them to the phone over Bluetooth Low Energy. The phone translates the dysarthric speech into clear audio and plays it aloud, and it turns the same signals into a running record of speech health so the patient (and later, if they choose, their care team) can see progression.

Success: the patient can be understood in a conversation with one tap or less, and can see an honest, readable trend of their speech over weeks.

## Positioning

Speech is captured at the throat, not through the air, so it works in noise and with very low-volume speech. The phone does the translation, so the band stays simple and the translator can improve over time without new hardware.

## Operating Context

- Current phase: the app connects to the ESP32 band over Bluetooth LE (protocol v1, `BandProtocol`; firmware in `firmware/`) and falls back to a simulated band until one is connected. Translation is still scripted, and histories are synthetic.
- Sessions happen in conversation: the patient starts listening, speaks, and the phone voices the translation.
- Progression review happens later, calmly, at home.
- Many patients have recorded or will record an iOS Personal Voice; the app should use it when authorized.

## Capabilities and Constraints

- Connect the band with minimal effort: one action, automatic reconnection, plain-language setup and troubleshooting. Show band status (battery and sensor contact when the band reports them).
- Visualize three live data streams: microphone, left piezo, right piezo.
- Compute per-session speech metrics and show their trend over time.
- Translate on-phone: `SpeechTranslator` protocol. Today only `ToyTranslator` (scripted phrases) conforms; the result is spoken aloud with AVSpeechSynthesizer (Personal Voice when authorized).
- Toy data drives every screen and is labeled as sample data.
- Undecided: skin-contact sensing and battery measurement on the band, the clinical translation model, clinical metric validation, any data sharing with clinicians.
- This is not a diagnostic device. Metrics are descriptive trends, never diagnoses.

## Brand Commitments

Name: Fonos. No logo provided yet.

## Evidence on Hand

No real patient data, clinical validation, or testimonials. Do not fabricate any. Demo mode data is synthetic and labeled as such.

## Product Principles

1. Being understood comes first. The speak action is always one large tap away.
2. Effort is expensive. Every interaction must work with minimal precise motor control.
3. Honest trends, gentle framing. Show change clearly without alarm or false precision.
4. Works without hardware. Every screen has a meaningful demo state.

## Accessibility & Inclusion

Primary user has progressive motor impairment and dysarthria. Required: minimum 60pt primary targets (44pt floor elsewhere), full VoiceOver and Switch Control support, Dynamic Type through accessibility sizes, Reduce Motion respected, no gesture-only actions, no time-limited interactions.
