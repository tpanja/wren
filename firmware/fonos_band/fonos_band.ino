// Fonos band firmware: streams the throat microphone and both piezos to the
// Fonos app over Bluetooth Low Energy. Protocol version 1, matching
// Fonos/Signal/BandProtocol.swift in the app. Change both together.
//
// Board: ESP32-S3 (dual core), Arduino core by Espressif 3.x, built-in BLE
// library (no extra libraries). Compile with:
//   arduino-cli compile --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=4M,PSRAM=enabled,PartitionScheme=huge_app" firmware/fonos_band
//
// Hardware, as wired on the current band (read from the board's previous
// firmware, dys_node 0.1.0):
//   - I2S digital microphone (e.g. INMP441): BCLK GPIO 13, WS GPIO 9, SD GPIO 11,
//     left slot (L/R pin to ground).
//   - Piezo 0 (left) on GPIO 1 = ADC1 channel 0; piezo 1 (right) on GPIO 2 = ADC1
//     channel 1. Each biased around mid-supply, within 0-3.3 V.
//
// The I2S clock paces everything: the mic runs at 16 kHz in 1/4 ms DMA
// chunks, the piezos are read after each chunk (4 kHz) and averaged in fours
// to 1 kHz, and the mic is averaged in pairs to 8 kHz. One 126-byte frame
// goes out every 10 ms:
//   0      protocol version (1)
//   1      flags: bit 0 left contact, bit 1 right contact, bit 2 contact reported, bit 3 charging
//   2-3    frame sequence, uint16 little-endian, wraps
//   4      battery percent 0-100, or 255 when unknown
//   5      reserved (0)
//   6-85   80 microphone samples at 8 kHz, G.711 mu-law
//   86-105 10 left piezo samples at 1 kHz, int16 little-endian
//   106-125 10 right piezo samples at 1 kHz, int16 little-endian

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "driver/i2s_std.h"

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------
#define MIC_BCLK_PIN 13
#define MIC_WS_PIN    9
#define MIC_SD_PIN   11
#define MIC_RIGHT_SLOT 0   // 0: mic's L/R pin to ground (left slot); 1: to 3.3 V
#define LEFT_PIN      1    // piezo 0, ADC1 channel 0
#define RIGHT_PIN     2    // piezo 1, ADC1 channel 1
#define BATTERY_PIN  -1    // ADC1 pin on a 1:2 divider from the cell; -1 if none

// Gains. The mic's 24-bit samples are taken as their top 16 bits, then
// multiplied by MIC_GAIN. The piezos' 12-bit readings are multiplied by
// PIEZO_GAIN (16 is unity to 16 bits). Raise a gain if the app's traces look
// small while speaking; lower it if they flatten at the edges.
#define MIC_GAIN      4
#define PIEZO_GAIN   16

#define DEVICE_NAME  "Fonos Band"
static const char* SERVICE_UUID = "079a0425-8a6e-4126-91c5-a5b5b2525f6b";
static const char* FRAMES_UUID  = "b5cff4bc-810e-4af7-8262-5f5f5d057ac5";

// ---------------------------------------------------------------------------

struct __attribute__((packed)) Frame {
  uint8_t  version;
  uint8_t  flags;
  uint16_t sequence;
  uint8_t  battery;
  uint8_t  reserved;
  uint8_t  mic[80];
  int16_t  left[10];
  int16_t  right[10];
};
static_assert(sizeof(Frame) == 126, "a Fonos frame is 126 bytes");

static BLECharacteristic* frames = nullptr;
static BLE2902* framesCCCD = nullptr;
static QueueHandle_t queue = nullptr;
static i2s_chan_handle_t mic = nullptr;
static volatile bool connected = false;
static volatile uint32_t sentThisSecond = 0;
static volatile uint32_t droppedThisSecond = 0;

// G.711 mu-law, the same encoder as BandProtocol.muLawEncode in the app.
static uint8_t muLawEncode(int16_t sample) {
  const int32_t BIAS = 0x84, CLIP = 32635;
  int32_t s = sample;
  uint8_t sign = 0;
  if (s < 0) { sign = 0x80; s = -s; }
  if (s > CLIP) s = CLIP;
  s += BIAS;
  uint8_t exponent = 7;
  for (int32_t mask = 0x4000; exponent > 0 && (s & mask) == 0; mask >>= 1) exponent--;
  uint8_t mantissa = (s >> (exponent + 3)) & 0x0F;
  return ~(sign | (exponent << 4) | mantissa);
}

static int16_t clamp16(float v) {
  if (v > 32767.0f) return 32767;
  if (v < -32768.0f) return -32768;
  return (int16_t)v;
}

static uint8_t readBattery() {
#if BATTERY_PIN >= 0
  uint32_t mv = analogReadMilliVolts(BATTERY_PIN) * 2;  // 1:2 divider
  if (mv <= 3300) return 0;
  if (mv >= 4200) return 100;
  return (uint8_t)((mv - 3300) * 100 / 900);
#else
  return 255;  // not measured
#endif
}

static bool startMic() {
  i2s_chan_config_t chan = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  chan.dma_desc_num = 16;
  chan.dma_frame_num = 4;  // one DMA buffer = 4 samples = 1/4 ms at 16 kHz
  if (i2s_new_channel(&chan, nullptr, &mic) != ESP_OK) return false;

  i2s_std_config_t std = {
    .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(16000),
    .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO),
    .gpio_cfg = {
      .mclk = I2S_GPIO_UNUSED,
      .bclk = (gpio_num_t)MIC_BCLK_PIN,
      .ws = (gpio_num_t)MIC_WS_PIN,
      .dout = I2S_GPIO_UNUSED,
      .din = (gpio_num_t)MIC_SD_PIN,
      .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
    },
  };
  std.slot_cfg.slot_mask = MIC_RIGHT_SLOT ? I2S_STD_SLOT_RIGHT : I2S_STD_SLOT_LEFT;
  if (i2s_channel_init_std_mode(mic, &std) != ESP_OK) return false;
  return i2s_channel_enable(mic) == ESP_OK;
}

// Builds one frame every 10 ms, paced by the I2S clock: 40 chunks of 4 mic
// samples (16 kHz), with both piezos read after each chunk (4 kHz).
static void samplerTask(void*) {
  Frame f = {};
  f.version = 1;
  uint16_t sequence = 0;
  uint8_t battery = readBattery();
  float micMean = 0, leftMean = 2048, rightMean = 2048;  // DC offset trackers
  int32_t chunk[4];

  for (;;) {
    f.sequence = sequence;
    f.battery = battery;
    f.flags = 0;  // contact sensing isn't wired; the app shows "not reported"
    int32_t leftSum = 0, rightSum = 0;

    for (int q = 0; q < 40; q++) {
      size_t got = 0;
      i2s_channel_read(mic, chunk, sizeof(chunk), &got, portMAX_DELAY);

      // Mic: top 16 bits of each 24-in-32-bit sample, DC removed, 16 kHz -> 8 kHz.
      for (int k = 0; k < 4; k += 2) {
        float a = (float)(chunk[k] >> 16), b = (float)(chunk[k + 1] >> 16);
        float s = 0.5f * (a + b);
        micMean += (s - micMean) * (1.0f / 1024);  // ~1 Hz high-pass at 8 kHz
        f.mic[q * 2 + k / 2] = muLawEncode(clamp16((s - micMean) * MIC_GAIN));
      }

      // Piezos at 4 kHz, averaged in fours to 1 kHz.
      leftSum += analogRead(LEFT_PIN);
      rightSum += analogRead(RIGHT_PIN);
      if ((q & 3) == 3) {
        float l = leftSum * 0.25f, r = rightSum * 0.25f;
        leftMean += (l - leftMean) * (1.0f / 64);   // ~2.5 Hz high-pass at 1 kHz
        rightMean += (r - rightMean) * (1.0f / 64);
        f.left[q >> 2] = clamp16((l - leftMean) * PIEZO_GAIN);
        f.right[q >> 2] = clamp16((r - rightMean) * PIEZO_GAIN);
        leftSum = rightSum = 0;
      }
    }

    if (xQueueSend(queue, &f, 0) != pdTRUE) droppedThisSecond++;
    sequence++;
    if (sequence % 100 == 0) battery = readBattery();  // once a second
  }
}

// Sends queued frames while the app is subscribed.
static void senderTask(void*) {
  Frame f;
  for (;;) {
    if (xQueueReceive(queue, &f, portMAX_DELAY) != pdTRUE) continue;
    if (!connected || framesCCCD == nullptr || !framesCCCD->getNotifications()) continue;
    frames->setValue((uint8_t*)&f, sizeof(f));
    frames->notify();
    sentThisSecond++;
  }
}

// Logs the link once a second.
static void statusTask(void*) {
  for (;;) {
    vTaskDelay(pdMS_TO_TICKS(1000));
    if (connected) Serial.printf("streaming: %u frames/s, %u dropped\n", sentThisSecond, droppedThisSecond);
    else Serial.println("advertising as " DEVICE_NAME ", waiting for the app");
    sentThisSecond = 0;
    droppedThisSecond = 0;
  }
}

// Core 3.3 uses NimBLE on the ESP32-S3 and Bluedroid on the classic ESP32;
// the connect callback differs between them.
class ServerCallbacks : public BLEServerCallbacks {
#if defined(CONFIG_NIMBLE_ENABLED)
  void onConnect(BLEServer* server, ble_gap_conn_desc* desc) override {
    onLinkUp();
    // 15-30 ms interval, the fastest iOS allows; several frames go per interval.
    server->updateConnParams(desc->conn_handle, 12, 24, 0, 400);
  }
#else
  void onConnect(BLEServer* server, esp_ble_gatts_cb_param_t* param) override {
    onLinkUp();
    server->updateConnParams(param->connect.remote_bda, 12, 24, 0, 400);
  }
#endif
  void onLinkUp() {
    connected = true;
    xQueueReset(queue);
    Serial.println("connected");
  }
  void onDisconnect(BLEServer*) override {
    connected = false;
    Serial.println("disconnected, advertising again");
    BLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  delay(300);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);  // 0-3.1 V range, as the previous firmware used

  queue = xQueueCreate(32, sizeof(Frame));
  if (!startMic()) Serial.println("# I2S mic failed to start: check MIC_*_PIN");

  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(247);  // a frame needs 129; iPhones negotiate 185 or more
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);
  frames = service->createCharacteristic(FRAMES_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  framesCCCD = new BLE2902();
  frames->addDescriptor(framesCCCD);
  service->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);  // the name goes in the scan response
  BLEDevice::startAdvertising();
  Serial.println("advertising as " DEVICE_NAME);

  xTaskCreatePinnedToCore(senderTask, "sender", 4096, nullptr, 4, nullptr, 0);
  xTaskCreatePinnedToCore(statusTask, "status", 3072, nullptr, 1, nullptr, 0);
  xTaskCreatePinnedToCore(samplerTask, "sampler", 6144, nullptr, 5, nullptr, 1);
}

void loop() {
  vTaskDelay(portMAX_DELAY);  // everything runs in the tasks above
}
