# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Delegated: native SwiftUI app, iOS 17+, Swift 5.9+, no third-party Swift packages. Apple frameworks only (SwiftUI, Charts, AVFoundation, Accelerate; CoreBluetooth when the band link is built). Bundled fonts are OFL-licensed (Atkinson Hyperlegible Next, Sora). LLM feedback comes from Anthropic's Claude API, called only from a small Fonos-operated feedback server, never from the app directly. Project generated with XcodeGen; the generated `.xcodeproj` is committed.

## Users

People who want to sing better and practice on their own with a throat band and an iPhone.

- **Default: hobbyists and beginners.** They practice alone, have no vocabulary for technique, and need plain, encouraging, specific feedback and short drills.
- **Optional: voice students.** People taking lessons who practice between sessions. A "Technical detail" setting reveals terms (cents, passaggio, onset, singer's formant) and fuller numbers.

## Product Purpose

Fonos is a singing coach. A throat band captures what the voice does from two sides at once: a microphone hears the sound, and two accelerometers on the left and right of the larynx feel the vibration at the skin. The phone analyzes both on-device, measures pitch, steadiness, vibrato, onsets, range, dynamics, tone, and throat vibration, and an LLM turns those numbers into short, specific coaching after each take.

Success: after a take, a singer knows the one thing to work on next and a drill to do it. Over weeks, they can see their pitch accuracy, steadiness, and range improve.

## Positioning

Pitch apps hear only the sound. Fonos also feels the vibration at the throat, on both sides, so it can coach what a microphone alone misses: how evenly the voice is produced, how the voice starts, and how hard the throat is working for the sound it makes. The vibration signal also keeps pitch tracking reliable in a noisy room.

## Operating Context

- Practice sessions at home: a warm-up, a few exercises (sirens, scales, sustained notes, a song phrase), and a speaking-voice check.
- Each take ends with a feedback card; progress review happens later.
- The singer holds or props up the phone while singing, so live screens are glanceable from arm's length.
- Current phase: the iOS app is a toy-data prototype. The Bluetooth link to the ESP32 band is not built yet.

## Capabilities and Constraints

- Inputs: microphone audio and two throat accelerometers (left and right of the larynx).
- All signal analysis runs on the phone.
- LLM feedback: the app sends computed metrics only (never audio or vibration signals) to the Fonos feedback server, which calls Claude and returns structured feedback. If feedback is turned off or unavailable, a local rule-based coach takes over.
- Privacy by design: raw audio and vibration are processed in memory and discarded unless the singer saves a take on the device. No account is required.
- Not a medical or voice-health device. Metrics describe singing; they never diagnose.
- Undecided: final sample rates and BLE packet format (spec proposes 16 kHz mic and 4 kHz accelerometers), feedback-server hosting, song library and licensing, teacher sharing.

## Brand Commitments

Name: Fonos. Dark-first visual world established in the prototype (slate ground, WHOOP-style rings, Apple Health-style cards, custom icon set, Sora and Atkinson Hyperlegible Next). The redesign keeps this world.

## Evidence on Hand

No user recordings, validation studies, teacher endorsements, or testimonials. All prototype data is synthetic and labeled as sample data. Do not fabricate results or accuracy claims.

## Product Principles

1. One thing to work on. Every take ends with a single focus and a drill, not a wall of numbers.
2. Numbers earn their place. Show a metric only when the singer can act on it; technical depth is opt-in.
3. Honest feedback. Feedback cites only what was measured, says when signal quality is low, and never diagnoses.
4. The voice stays on the phone. Audio and vibration never leave the device; only numbers do, and only with consent.
5. Glanceable while singing. Live screens read from arm's length with no fine taps.

## Accessibility & Inclusion

Dynamic Type through accessibility sizes, full VoiceOver support (live pitch announced on request, not continuously), Reduce Motion respected, 44 pt minimum targets and 60 pt+ for primary actions, color never the only signal for in-tune versus out-of-tune, and captions or haptics for any audio cue.
