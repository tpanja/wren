# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Delegated: native SwiftUI app, iOS 17+, Swift 5.9+, no third-party packages. Frameworks used are Apple-only (CoreBluetooth, AVFoundation, Speech, Charts, SwiftData-free JSON persistence). Project generated with XcodeGen (`project.yml`) and the generated `.xcodeproj` is committed so it opens directly in Xcode.

## Users

The person living with ALS who wears the Fonos throat band. They hold and operate the phone themselves, typically with dysarthric speech and declining hand and arm function that worsens over months. They use it at home and out in the world to be understood by others, and to watch how their speech is changing.

## Product Purpose

Fonos turns throat vibration into clear speech. The band captures three streams (one contact microphone, two piezo vibration sensors on either side of the larynx) and streams them to the phone over Bluetooth Low Energy. The phone translates the dysarthric speech into clear audio and plays it aloud, and it turns the same signals into a running record of speech health so the patient (and later, if they choose, their care team) can see progression.

Success: the patient can be understood in a conversation with one tap or less, and can see an honest, readable trend of their speech over weeks.

## Positioning

Speech is captured at the throat, not through the air, so it works in noise and with very low-volume speech. The phone does the translation, so the band stays simple and the translator can improve over time without new hardware.

## Operating Context

- Band connects over BLE to an ESP32 (custom Fonos GATT service, defined in this repo under `Docs/BLUETOOTH.md`).
- Sessions happen in conversation: the patient starts listening, speaks, and the phone voices the translation.
- Progression review happens later, calmly, at home.
- Many patients have recorded or will record an iOS Personal Voice; the app should use it when authorized.

## Capabilities and Constraints

- Connect, reconnect, and show band status (battery, signal, streaming).
- Visualize three live data streams: microphone, left piezo, right piezo.
- Compute per-session speech metrics and show their trend over time.
- Translate on-phone: `SpeechTranslator` protocol. Shipped implementation uses on-device Apple speech recognition on the throat-mic stream and speaks the result with AVSpeechSynthesizer (Personal Voice when authorized). A Core ML translator can replace it without UI changes.
- Demo mode simulates the band so the app is fully usable without hardware.
- Undecided: the clinical translation model, clinical metric validation, any data sharing with clinicians.
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
