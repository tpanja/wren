// Fonos band firmware: streams the contact microphone and both piezos to the
// Fonos app over Bluetooth Low Energy. Protocol version 1, matching
// Fonos/Signal/BandProtocol.swift in the app. Change both together.
//
// Board: a dual-core ESP32 (ESP32 DevKit, or ESP32-S3 with ADC1 pins
// GPIO 1-10), Arduino core by Espressif 2.x or 3.x, with the built-in BLE
// library (no extra libraries). Single-core chips such as the ESP32-C3 need
// the sampler moved to core 0.
//
// Every 10 ms the band sends one 126-byte frame:
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

// ---------------------------------------------------------------------------
// Wiring. Use ADC1 pins only: ADC2 can't be read while the radio is on.
// Each sensor's signal must sit around mid-supply (about 1.65 V) and stay
// within 0-3.3 V; the firmware removes the DC offset itself.
// ---------------------------------------------------------------------------
#define MIC_PIN      34   // contact microphone (through its preamp)
#define LEFT_PIN     32   // left piezo
#define RIGHT_PIN    33   // right piezo
#define LED_PIN       2   // onboard LED on most ESP32 DevKits; -1 for none
#define BATTERY_PIN  -1   // ADC1 pin on a 1:2 divider from the cell; -1 if none

// 12-bit ADC to 16-bit samples: 16 is unity. Raise a gain if the app's
// traces look small while speaking; lower it if they clip at the edges.
#define MIC_GAIN     16
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

// Samples the mic at 8 kHz and the piezos at 1 kHz, paced by the
// microsecond timer, and queues one frame every 10 ms. Runs alone on core 1
// so the timing stays steady; Bluetooth runs on core 0.
static void samplerTask(void*) {
  Frame f = {};
  f.version = 1;
  uint16_t sequence = 0;
  uint8_t battery = readBattery();
  float micMean = 2048, leftMean = 2048, rightMean = 2048;  // DC offset trackers
  int64_t next = esp_timer_get_time();

  for (;;) {
    f.sequence = sequence;
    f.battery = battery;
    f.flags = 0;  // contact sensing isn't wired; the app shows "not reported"

    for (int i = 0; i < 80; i++) {
      next += 125;  // 8 kHz
      while (esp_timer_get_time() < next) { }
      int raw = analogRead(MIC_PIN);
      micMean += (raw - micMean) * (1.0f / 512);  // ~2.5 Hz high-pass
      f.mic[i] = muLawEncode(clamp16((raw - micMean) * MIC_GAIN));

      if ((i & 7) == 0) {  // every 8th mic sample: 1 kHz
        int k = i >> 3;
        int l = analogRead(LEFT_PIN), r = analogRead(RIGHT_PIN);
        leftMean += (l - leftMean) * (1.0f / 64);
        rightMean += (r - rightMean) * (1.0f / 64);
        f.left[k] = clamp16((l - leftMean) * PIEZO_GAIN);
        f.right[k] = clamp16((r - rightMean) * PIEZO_GAIN);
      }
    }

    if (xQueueSend(queue, &f, 0) != pdTRUE) droppedThisSecond++;
    sequence++;
    if (sequence % 100 == 0) battery = readBattery();  // once a second

    // If something stalled us for more than a frame, resync instead of
    // racing through samples to catch up.
    int64_t now = esp_timer_get_time();
    if (now - next > 10000) next = now;
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

// Blinks while waiting for the phone, stays on while connected, and logs
// the frame rate once a second.
static void statusTask(void*) {
  bool on = false;
  uint32_t ticks = 0;
  for (;;) {
    vTaskDelay(pdMS_TO_TICKS(500));
    on = connected ? true : !on;
    if (LED_PIN >= 0) digitalWrite(LED_PIN, on ? HIGH : LOW);
    if (++ticks % 2 == 0) {
      if (connected) Serial.printf("streaming: %u frames/s, %u dropped\n", sentThisSecond, droppedThisSecond);
      sentThisSecond = 0;
      droppedThisSecond = 0;
    }
  }
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server, esp_ble_gatts_cb_param_t* param) override {
    connected = true;
    xQueueReset(queue);
    // 15-30 ms interval, the fastest iOS allows; several frames go per interval.
    server->updateConnParams(param->connect.remote_bda, 12, 24, 0, 400);
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
  if (LED_PIN >= 0) pinMode(LED_PIN, OUTPUT);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);  // 0-3.3 V range

  queue = xQueueCreate(32, sizeof(Frame));

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

  // The sampler spins between samples to keep exact timing, so core 1's
  // idle watchdog must be off (it is by default in the Arduino core). It is
  // created last: setup() itself runs on core 1, and the sampler takes core 1
  // over from here on.
  disableCore1WDT();
  xTaskCreatePinnedToCore(samplerTask, "sampler", 4096, nullptr, 5, nullptr, 1);
}

void loop() {
  // Never reached: the sampler owns core 1. Everything runs in the tasks above.
  vTaskDelay(portMAX_DELAY);
}
