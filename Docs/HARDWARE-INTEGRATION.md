# Hardware integration

Wren connects to the ESP32 throat band over Bluetooth Low Energy. The firmware lives in [`firmware/`](../firmware/README.md); its README covers flashing, wiring, gains, and the wire format.

## The seam: `FrameSource`

```swift
protocol FrameSource: AnyObject {
    var onFrame: (@Sendable (SensorFrame) -> Void)? { get set }
    var status: BandStatus { get }
    func startStreaming()
    func stopStreaming()
}
```

Two sources conform: `ToyBand` (simulated) and `BluetoothBand` (the real band). `FonosEngine` routes both into the same pipeline (`StreamStore`, `SpeechAnalyzer`, the translator), and `bandMode` picks which one feeds it. Nothing downstream knows which band it is. Sessions and checks recorded from the real band are not marked as sample data.

## Protocol v1 (`BandProtocol`)

- The band advertises as **Wren Band** (firmware before the rename: **Wren Band**) with service `079A0425-8A6E-4126-91C5-A5B5B2525F6B`.
- One notify characteristic, `B5CFF4BC-810E-4AF7-8262-5F5F5D057AC5`, carries 126-byte frames, each 10 ms: a 6-byte header (version, flags, sequence, battery), 80 µ-law mic samples at 8 kHz, and 10 Int16 samples per piezo at 1 kHz. A notification may hold several frames.
- `BandProtocol.decode` rejects partial frames and other versions. `BandProtocolTests` pins the layout, µ-law against G.711 reference codes, multi-frame notifications, and sequence wraparound. `BandProtocol.encode` mirrors the firmware's encoder.

## Connecting (`BluetoothBand`)

- CoreBluetooth runs on its own queue; frames go straight to `onFrame` there, like the simulated band. The engine polls `snapshot` 10 times a second for the UI, so the main thread never sees frame-rate data.
- Bluetooth starts (and iOS asks for permission) only when the user taps Connect, or at launch if a band was connected before.
- **First connection:** a scan filtered to the Wren service. With one band nearby, Wren connects after two seconds; with more, the user picks one. The chosen band's identifier is remembered.
- **Reconnection:** at launch and after any drop, Wren issues a connect request for the remembered band. iOS keeps that request open indefinitely, so the band reconnects whenever it's on and in range. "Forget this band" clears it.
- **Lost frames:** the sequence number shows gaps. Up to half a second of lost frames is filled with silence so durations and rates stay right, and the count is kept in `snapshot.droppedFrames`. The Band page calls the signal patchy below 85 frames a second.
- **Backgrounding:** the app unsubscribes from notifications in the background and resubscribes when active; the connection stays up.
- **Speak flow:** with the real band, listening stops after the chosen seconds of quiet once speech has started (the simulated band uses a timer instead). Speech check tasks detect the voice 15 dB above the task's own quietest moment, so they work at any band gain.

## Permissions

`NSBluetoothAlwaysUsageDescription` is set in `project.yml`. Background streaming (the `bluetooth-central` background mode) is not enabled: Wren stops streaming when it leaves the screen, as before.

## Still to do

- Run the app itself against the band. The firmware and protocol are verified on the real board (100 frames a second, no losses, decoded by `BandProtocol` over Bluetooth from a Mac), but the app's connection flow has only run in the iOS Simulator, which has no Bluetooth.
- Skin-contact sensing and battery measurement on the band (the protocol already has fields for both).
- A real translator: `SpeechTranslator` is the seam. `ToyTranslator` still returns scripted phrases even when the real band is connected.

## Translation

`SpeechTranslator` is the matching seam for translation. `ToyTranslator` returns scripted phrases. A real translator (on-device speech recognition, or a model fine-tuned on the patient's own recordings) conforms to the same protocol and receives the mic stream through `append(mic:)`.
