# Wren Band firmware

`fonos_band/fonos_band.ino` runs the Wren Band (an ESP32-S3 with an I2S throat microphone and two piezos): it streams the mic at 8 kHz and both piezos at 1 kHz to the Wren app over Bluetooth Low Energy. The app side of the protocol is `Fonos/Signal/BandProtocol.swift`; change both together.

## Flash it

From the repo root, with the board on USB (the port name may differ):

```bash
arduino-cli core install esp32:esp32
arduino-cli compile --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=4M,PSRAM=enabled,PartitionScheme=huge_app" firmware/fonos_band
arduino-cli upload -p /dev/cu.usbmodem1101 --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=4M,PSRAM=enabled,PartitionScheme=huge_app" firmware/fonos_band
```

In the Arduino IDE the same settings are: board **ESP32S3 Dev Module**, USB Mode **Hardware CDC and JTAG**, USB CDC On Boot **Enabled**, Flash Size **4MB**, PSRAM **Enabled**, Partition Scheme **Huge APP**. The Bluetooth stack doesn't fit the default partition.

The serial console (115200 baud) prints `advertising as Wren Band, waiting for the app` once a second, then `streaming: 100 frames/s, 0 dropped` while the app is connected.

## Connect it to the app

Open Wren → **Band** → **Connect your band**, and allow Bluetooth. Wren finds the band and connects, and after that reconnects on its own whenever the band is on and in range. Don't pair the band in iPhone Settings → Bluetooth; it connects from the app only.

## Wiring

Read from the board's previous firmware (`dys_node` 0.1.0) by inspecting its pin routing over the ESP32-S3's built-in debug port:

| Signal | GPIO | Notes |
|---|---|---|
| Mic I2S bit clock (BCLK) | 13 | I2S digital mic, e.g. INMP441 |
| Mic I2S word select (WS) | 9 | |
| Mic I2S data (SD) | 11 | Left slot (mic L/R pin to ground) |
| Left piezo | 1 | ADC1 channel 0, 0–3.1 V |
| Right piezo | 2 | ADC1 channel 1, 0–3.1 V |

Piezos must use ADC1 pins (GPIO 1–10 on the S3); ADC2 can't be read while the radio is on. Each piezo signal should sit around mid-supply and stay within the ADC range; the firmware removes the DC offset itself. The previous firmware is backed up in `firmware/backup/` on the Mac that flashed it (not in git); restore it with `esptool write-flash 0 original-firmware.bin`.

## Tuning

- **`MIC_GAIN`** (default 4) scales the mic's top 16 bits; **`PIEZO_GAIN`** (default 16, unity from 12 bits). Raise a gain if the app's traces look small while speaking, lower it if they flatten at the edges.
- **Battery**: set `BATTERY_PIN` to an ADC1 pin on a 1:2 divider to show the charge in the app.
- **Skin contact** isn't sensed yet, so the app doesn't show a contact state. Bits 0–2 of `flags` carry it when a sensor exists.
- **Left and right**: GPIO 1 is sent as the left piezo. If the app's balance looks mirrored, swap `LEFT_PIN` and `RIGHT_PIN`.

## Protocol (version 1)

- Advertised name **Wren Band** (**Wren Band** before the rename; the app shows either as Wren Band), with service `079A0425-8A6E-4126-91C5-A5B5B2525F6B` in the advertisement.
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

## Verified

On the band (ESP32-S3, 4 MB flash, 2 MB PSRAM), with Espressif core 3.3.12: the firmware compiles (615 KB, 19% of the app partition), flashes, and streams. A Mac test client using the app's `BandProtocol` decoder over real Bluetooth received 100.0 frames a second for 10 seconds with no lost or undecodable frames, with live levels on the mic (−24 dBFS RMS) and both piezos (−38 and −46 dBFS).
