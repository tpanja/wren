# Hardware integration (not built yet)

The Bluetooth connection to the ESP32 throat band is intentionally out of scope for this phase. The app runs on toy data so the experience can be designed and reviewed before the hardware link exists. This note records where the real band will plug in, so that work stays small when it starts.

## The seam: `FrameSource`

`Fonos/Signal/ToyBand.swift` defines:

```swift
protocol FrameSource: AnyObject {
    var onFrame: (@Sendable (SensorFrame) -> Void)? { get set }
    var status: BandStatus { get }
    func startStreaming()
    func stopStreaming()
}
```

`ToyBand` is the only conforming type today. A future `BluetoothBand` would:

1. Use CoreBluetooth to find and connect to the band, and remember it for automatic reconnection.
2. Decode each notification into a `SensorFrame` (80 mic samples at 8 kHz, 10 samples per piezo at 1 kHz, normalized to −1…1).
3. Report battery and sensor contact through `BandStatus`.
4. Call `onFrame` on a background queue.

`FonosEngine` would then hold a `FrameSource` instead of a concrete `ToyBand`. Nothing in `StreamStore`, `SpeechAnalyzer`, the translator, or any screen needs to change.

## Still to decide with the firmware

- GATT service and characteristic layout, and how frames are packed. The rates above need about 16 KB/s of 16-bit audio; 8-bit µ-law for the mic would halve that and fit a 10 ms frame in one notification at the default iOS MTU.
- How sensor contact is detected on the band.
- Connection UX: first-time pairing screen, reconnect behavior, and what the Band tab shows while disconnected.
- Permissions to add at that point: `NSBluetoothAlwaysUsageDescription` and, for background streaming, the `bluetooth-central` background mode.

## Translation

`SpeechTranslator` is the matching seam for translation. `ToyTranslator` returns scripted phrases. A real translator (on-device speech recognition, or a model fine-tuned on the patient's own recordings) conforms to the same protocol and receives the mic stream through `append(mic:)`.
