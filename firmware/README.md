# Fonos band firmware

`fonos_band/fonos_band.ino` turns an ESP32 into the Fonos band: it samples the contact microphone at 8 kHz and both piezos at 1 kHz, and streams them to the Fonos app over Bluetooth Low Energy. The app side of the protocol is `Fonos/Signal/BandProtocol.swift`; change both together.

## Flash it

1. Install the [Arduino IDE](https://www.arduino.cc/en/software).
2. In **Boards Manager**, install **esp32 by Espressif Systems** (2.x or 3.x).
3. Open `firmware/fonos_band/fonos_band.ino`.
4. Check the pin settings at the top of the file against your wiring (see below).
5. **Tools → Board**: pick your board, for example **ESP32 Dev Module** or **ESP32S3 Dev Module**.
6. Connect the board by USB, pick its port under **Tools → Port**, and click **Upload**.
7. Open **Tools → Serial Monitor** at 115200 baud. You should see `advertising as Fonos Band`, and the onboard light starts blinking.

## Connect it to the app

On the iPhone, open Fonos → **Band** → **Connect your band**, and allow Bluetooth. Fonos finds the band and connects; the light stays on, and the Serial Monitor prints `streaming: 100 frames/s, 0 dropped` once a second. After that, Fonos reconnects on its own whenever the band is on and in range.

Don't pair the band in iPhone Settings → Bluetooth. Bluetooth LE devices like this connect from the app, and won't show up there.

## Wiring

| Signal | Default pin | Notes |
|---|---|---|
| Contact microphone | GPIO 34 | Through its preamp |
| Left piezo | GPIO 32 | |
| Right piezo | GPIO 33 | |
| Status light | GPIO 2 | Onboard LED on most DevKits; `-1` for none |
| Battery | none | Optional: an ADC1 pin on a 1:2 divider from the cell |

- Use **ADC1 pins only**. ADC2 can't be read while the radio is on. On an ESP32-S3, ADC1 is GPIO 1–10.
- Each signal must sit around **mid-supply (about 1.65 V)** and stay within 0–3.3 V. The firmware removes the DC offset itself, but it can't recover a signal that is clipped at 0 V or 3.3 V.
- A dual-core chip is assumed (the sampler has core 1 to itself). An ESP32-C3 or other single-core chip needs the sampler moved to core 0.

## Tuning

- **`MIC_GAIN`, `PIEZO_GAIN`** (default 16, which is unity from 12 bits to 16 bits). If the traces on the app's Band page look small while you speak, raise the gain. If they flatten against the top and bottom, lower it.
- **Battery**: set `BATTERY_PIN` to show the band's charge in the app. Without it, the app shows the battery as unknown.
- **Skin contact**: the firmware doesn't sense contact yet, so the app doesn't show a contact state. When a contact sensor exists, set bits 0–2 of `flags` (see the protocol below).

## Protocol (version 1)

- Advertised name **Fonos Band**, with service `079A0425-8A6E-4126-91C5-A5B5B2525F6B` in the advertisement.
- One characteristic, `B5CFF4BC-810E-4AF7-8262-5F5F5D057AC5`, notify only.
- Each notification carries one or more 126-byte frames, each 10 ms of signal, little-endian:

| Bytes | Field |
|---|---|
| 0 | Protocol version, 1 |
| 1 | Flags: bit 0 left contact, bit 1 right contact, bit 2 contact is reported, bit 3 charging |
| 2–3 | Frame sequence, UInt16, wraps. The app uses gaps to count lost frames and keep time. |
| 4 | Battery percent 0–100, or 255 when unknown |
| 5 | Reserved, 0 |
| 6–85 | 80 microphone samples at 8 kHz, G.711 µ-law |
| 86–105 | 10 left piezo samples at 1 kHz, Int16 |
| 106–125 | 10 right piezo samples at 1 kHz, Int16 |

That's 12.6 KB/s. A frame needs an MTU of at least 129; iPhones negotiate 185 or more. The firmware asks for a 15–30 ms connection interval, the fastest iOS allows, and several frames go out per interval.

## Not tested yet

This firmware was written against the ESP32 Arduino core's BLE library but hasn't been compiled or run on a board here. If it doesn't build for your board or core version, the likely spots are `analogSetAttenuation(ADC_11db)` (renamed in some 3.x releases) and the `onConnect` callback signature.
