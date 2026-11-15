import CoreBluetooth
import Foundation
import os

/// The real Fonos band over Bluetooth Low Energy (see `BandProtocol`).
///
/// CoreBluetooth runs on its own queue and frames go straight to `onFrame`
/// on that queue, like the simulated band. The UI reads `snapshot` (the
/// engine polls it 10 times a second), so nothing here touches the main thread.
///
/// The first connection is chosen by the user; after that the band is
/// remembered and Fonos reconnects whenever it is in range. An iOS connect
/// request never times out, so a band that is off or out of range simply
/// connects when it comes back.
final class BluetoothBand: NSObject, FrameSource, @unchecked Sendable {

    enum State: Equatable, Sendable {
        /// Bluetooth hasn't been started this session (no permission prompt yet).
        case notStarted
        /// This device has no Bluetooth LE (the iOS Simulator, for one).
        case unsupported
        /// The user declined Bluetooth access for Fonos.
        case unauthorized
        case poweredOff
        /// Bluetooth is on; no band connected and none being looked for.
        case idle
        case scanning
        case connecting(String)
        case connected(String)
        /// A remembered band dropped or is out of range; Fonos is waiting for it.
        case waiting(String)
    }

    struct Found: Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        var rssi: Int
        var lastSeen: Date
    }

    struct Snapshot: Equatable, Sendable {
        var state: State = .notStarted
        var found: [Found] = []
        var status = BandStatus(battery: nil, leftContact: nil, rightContact: nil, isCharging: false)
        var rssi: Int?
        /// Frames received in the last full second, and lost since connecting.
        var framesPerSecond = 0
        var droppedFrames = 0
        var lastError: String?
    }

    var onFrame: (@Sendable (SensorFrame) -> Void)?

    var status: BandStatus { lock.withLock { $0.status } }
    var snapshot: Snapshot { lock.withLock { $0 } }

    private static let rememberedKey = "fonos.band.peripheral"
    static var remembered: UUID? {
        UserDefaults.standard.string(forKey: rememberedKey).flatMap(UUID.init(uuidString:))
    }

    private let queue = DispatchQueue(label: "fonos.bluetooth", qos: .userInitiated)
    private let lock = OSAllocatedUnfairLock(initialState: Snapshot())
    // Owned by `queue`.
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var framesCharacteristic: CBCharacteristic?
    private var wantsStream = false
    /// The user asked to look for bands before Bluetooth was ready.
    private var pendingScan = false
    private var lastSequence: UInt16?
    private var countThisSecond = 0
    private var secondStarted = Date()
    private var rssiTimer: DispatchSourceTimer?

    // MARK: Control (callable from any thread)

    /// Starts Bluetooth (the first call shows the permission prompt) and
    /// reconnects to the remembered band if there is one.
    func activate() {
        queue.async { [self] in
            guard central == nil else { return }
            central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
    }

    func scan() {
        queue.async { [self] in
            guard let central, central.state == .poweredOn else {
                pendingScan = true
                if central == nil {
                    central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
                }
                return
            }
            startScan(central)
        }
    }

    private func startScan(_ central: CBCentralManager) {
        pendingScan = false
        update { $0.found = []; $0.lastError = nil; $0.state = .scanning }
        central.scanForPeripherals(withServices: [BandProtocol.service],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Reconnects to the remembered band (starting Bluetooth if needed).
    func reconnect() {
        queue.async { [self] in
            guard let central else { activate(); return }
            if central.state == .poweredOn, peripheral == nil { reconnectRemembered() }
        }
    }

    func stopScan() {
        queue.async { [self] in
            central?.stopScan()
            if case .scanning = snapshot.state { update { $0.state = .idle } }
        }
    }

    func connect(_ id: UUID) {
        queue.async { [self] in
            guard let central, let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
            central.stopScan()
            UserDefaults.standard.set(id.uuidString, forKey: Self.rememberedKey)
            attach(p)
        }
    }

    /// Disconnects. With `forget`, the band is no longer reconnected automatically.
    func disconnect(forget: Bool) {
        queue.async { [self] in
            if forget { UserDefaults.standard.removeObject(forKey: Self.rememberedKey) }
            if let p = peripheral { central?.cancelPeripheralConnection(p) }
            peripheral = nil
            framesCharacteristic = nil
            stopRSSI()
            update { $0.state = .idle; $0.rssi = nil; $0.framesPerSecond = 0 }
        }
    }

    // MARK: FrameSource

    func startStreaming() {
        queue.async { [self] in
            wantsStream = true
            if let p = peripheral, let c = framesCharacteristic { p.setNotifyValue(true, for: c) }
        }
    }

    func stopStreaming() {
        queue.async { [self] in
            wantsStream = false
            if let p = peripheral, let c = framesCharacteristic, p.state == .connected { p.setNotifyValue(false, for: c) }
        }
    }

    // MARK: Private

    private func update(_ body: (inout Snapshot) -> Void) {
        lock.withLock { body(&$0) }
    }

    private func name(_ p: CBPeripheral, advertised: String? = nil) -> String {
        guard let n = advertised ?? p.name, !BandProtocol.legacyNames.contains(n) else { return BandProtocol.advertisedName }
        return n
    }

    private func attach(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        lastSequence = nil
        update { $0.state = .connecting(name(p)); $0.droppedFrames = 0 }
        central?.connect(p, options: nil)
    }

    private func reconnectRemembered() {
        guard let central, let id = Self.remembered,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else {
            update { $0.state = .idle }
            return
        }
        attach(p)
        update { $0.state = .waiting(name(p)) }
    }

    private func startRSSI() {
        stopRSSI()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 2)
        t.setEventHandler { [weak self] in self?.peripheral?.readRSSI() }
        t.resume()
        rssiTimer = t
    }

    private func stopRSSI() {
        rssiTimer?.cancel()
        rssiTimer = nil
    }

    private func receive(_ data: Data) {
        let packets: [BandProtocol.Packet]
        do { packets = try BandProtocol.decode(data) } catch {
            update { $0.lastError = "The band sent data Wren can't read. Update the band's firmware." }
            return
        }
        for packet in packets {
            if let last = lastSequence {
                // Keep the time base honest: stand in silence for lost frames
                // (up to half a second) so durations and rates stay right.
                let lost = BandProtocol.missing(after: last, next: packet.sequence)
                if lost > 0 {
                    update { $0.droppedFrames += lost }
                    let silent = SensorFrame(mic: Array(repeating: 0, count: BandProtocol.micSamples),
                                             left: Array(repeating: 0, count: BandProtocol.piezoSamples),
                                             right: Array(repeating: 0, count: BandProtocol.piezoSamples))
                    for _ in 0..<min(lost, 50) { onFrame?(silent) }
                }
            }
            lastSequence = packet.sequence
            onFrame?(packet.frame)
            countThisSecond += 1
            update {
                $0.status = BandStatus(battery: packet.battery, leftContact: packet.leftContact,
                                       rightContact: packet.rightContact, isCharging: packet.charging)
            }
        }
        if Date().timeIntervalSince(secondStarted) >= 1 {
            let n = countThisSecond
            update { $0.framesPerSecond = n }
            countThisSecond = 0
            secondStarted = Date()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothBand: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingScan { startScan(central) } else { reconnectRemembered() }
        case .poweredOff: update { $0.state = .poweredOff; $0.framesPerSecond = 0 }
        case .unauthorized: update { $0.state = .unauthorized }
        case .unsupported: update { $0.state = .unsupported }
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi < 0 else { return } // 127 means "unavailable"
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let found = Found(id: p.identifier, name: name(p, advertised: advertised), rssi: rssi, lastSeen: Date())
        update { s in
            if let i = s.found.firstIndex(where: { $0.id == found.id }) { s.found[i] = found } else { s.found.append(found) }
            s.found.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        update { $0.state = .connecting(name(p)) }
        p.discoverServices([BandProtocol.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        update { $0.lastError = "Couldn't connect to the band. Turn it off and on, then try again." }
        // Keep trying in the background; iOS connects when it can.
        if p.identifier == Self.remembered { attach(p); update { $0.state = .waiting(name(p)) } }
        else { update { $0.state = .idle } }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        framesCharacteristic = nil
        stopRSSI()
        update { $0.framesPerSecond = 0; $0.rssi = nil }
        // Unexpected drop of the remembered band: wait for it to come back.
        if peripheral?.identifier == p.identifier, p.identifier == Self.remembered {
            attach(p)
            update { $0.state = .waiting(name(p)) }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothBand: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == BandProtocol.service }) else {
            update { $0.lastError = "This device isn't a Wren Band, or its firmware is out of date." }
            central?.cancelPeripheralConnection(p)
            return
        }
        p.discoverCharacteristics([BandProtocol.frames], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let c = service.characteristics?.first(where: { $0.uuid == BandProtocol.frames }) else {
            update { $0.lastError = "The band's firmware is out of date. Flash the current Wren firmware." }
            return
        }
        framesCharacteristic = c
        lastSequence = nil
        if wantsStream { p.setNotifyValue(true, for: c) }
        update { $0.state = .connected(name(p)); $0.lastError = nil }
        startRSSI()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard error == nil, c.uuid == BandProtocol.frames, let data = c.value else { return }
        receive(data)
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        update { $0.rssi = RSSI.intValue }
    }
}
