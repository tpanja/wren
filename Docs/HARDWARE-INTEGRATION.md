# Hardware integration

The Bluetooth link to the ESP32 throat band is not built yet. This note records what the singing coach needs from the band and where it plugs into the app, so the firmware and app work can proceed in parallel.

## What the band must provide

| Stream | Sensor | Proposed rate | Notes |
|---|---|---|---|
| Mic | Microphone at the front of the neck | 16 kHz | 16 kHz keeps the 2–4 kHz "ring" band measurable; µ-law to 8 bits over BLE |
| Left accel | 3-axis accelerometer, left of the larynx | 4 kHz voice band | Send the dominant axis or vector magnitude; ±8 g range |
| Right accel | Same, right side | 4 kHz voice band | |
| Left/right motion | Same accelerometers, low-pass | 100 Hz | Slow laryngeal movement under 15 Hz |
| Status | — | On change and every 5 s | Battery, charging, per-side contact, firmware version |

- All streams are packed into 10 ms frames with a shared timestamp and a sequence number, so the phone can align them and detect drops.
- **Throughput:** about 16 KB/s for the mic plus about 16 KB/s for both accelerometers (16-bit, one axis each), roughly 32 KB/s in total. That needs BLE 2M PHY and data-length extension. If the link can't sustain it, the fallback is 12 kHz mic and 3 kHz accelerometers.
- **Contact detection** happens on the phone (vibration present while the mic hears voicing); the band only reports gross contact if it can.

## Where it plugs in

The app reads frames through one protocol (`FrameSource`, today in `Fonos/Signal/ToyBand.swift`):

- `onFrame` delivers each 10 ms frame on a background queue.
- `status` reports battery and contact.
- `startStreaming()` and `stopStreaming()`.

Today only the toy band conforms. A future `BluetoothBand` will:

1. Use CoreBluetooth to find the band, connect, and remember it for automatic reconnection.
2. Decode notifications into frames at the rates above.
3. Report status.

Nothing in the analysis or UI changes when it is swapped in.

## Still to decide with the firmware

- GATT service and characteristic layout, frame packing, MTU
- Accelerometer part, axis choice, and on-band filtering
- Pairing and reconnect UX (the Band tab's fit check doubles as the connection check)
- App permissions at that point: `NSBluetoothAlwaysUsageDescription`, and `bluetooth-central` for background streaming if needed
