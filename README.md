# Fonos

A singing coach for iPhone and the Fonos throat band. The band hears the voice through a microphone and feels it through two accelerometers on either side of the larynx. The phone analyzes both on-device, and after each take Fonos gives one clear thing to work on, with a drill.

## Status

- **Specification:** drafted and awaiting approval. Start with [Docs/SPEC.md](Docs/SPEC.md).
- **iOS code:** a toy-data SwiftUI prototype from an earlier product direction. It is rebuilt to this spec next; [Docs/SPEC.md § 9](Docs/SPEC.md#9-migration-plan-from-the-current-prototype) lists the changes. The visual world (palette, type, icons, rings, cards) carries over.
- **Hardware link:** the Bluetooth connection to the ESP32 band is not built yet.

## Documentation

| Document | What it covers |
|---|---|
| [PRODUCT.md](PRODUCT.md) | Who Fonos is for, what it does, principles |
| [Docs/SPEC.md](Docs/SPEC.md) | App specification: flows, metrics, LLM feedback summary, privacy, migration plan |
| [Docs/SINGING-ANALYSIS.md](Docs/SINGING-ANALYSIS.md) | Outline of the speech and singing analysis documentation: data collection, processing, interpretation |
| [Docs/LLM-FEEDBACK.md](Docs/LLM-FEEDBACK.md) | Feedback server, Claude request, system prompt, payload, output schema, sample feedback |
| [Docs/UI-REDESIGN.md](Docs/UI-REDESIGN.md) | Screen-by-screen mock-up descriptions |
| [Docs/HARDWARE-INTEGRATION.md](Docs/HARDWARE-INTEGRATION.md) | What the band must provide, and where it plugs into the app |

## Run the prototype

Requirements: Xcode 15 or later, iOS 17 or later. No third-party Swift packages. The bundled fonts (Atkinson Hyperlegible Next and Sora) are OFL-licensed assets in `Fonos/Resources/Fonts`.

```bash
open Fonos.xcodeproj
```

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or moving files:

```bash
xcodegen generate
```

## Privacy

Audio and vibration are analyzed on the phone and never uploaded. With the singer's consent, only computed measurements go to the Fonos feedback server, which asks Claude for coaching. See [Docs/SPEC.md § 7](Docs/SPEC.md#7-privacy-by-design).

Fonos is not a medical device and does not diagnose.
