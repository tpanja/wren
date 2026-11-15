import CoreBluetooth
import Foundation
import Observation

/// Owns the CoreBluetooth central and the link to one Fonos band.
///
/// Lifecycle: power on → scan for the Fonos service → connect → discover
/// characteristics → subscribe to status → (on request) subscribe to stream
/// and write `startStream`. The last connected band is remembered and
/// reconnected automatically, so the patient does not have to pair again.
@Observable
final class BandConnection: NSObject, FrameSource {

    enum State: Equatable {
        case poweredOff
        case unauthorized
        case unsupported
        case idle
        case scanning
        case connecting(String)
        case connected(String)
        case reconnecting(String)
    }

    struct Discovered: Identifiable, Equatable {
        let id: UUID
        let name: String
        var rssi: Int
    }

    private(set) var state: State = .idle
    private(set) var discovered: [Discovered] = []
    private(set) var status = BandStatus()
    private(set) var rssi: Int?
    private(set) var droppedFrames = 0
    private(set) var lastError: String?

    @ObservationIgnored var onFrame: (@Sendable (SensorFrame) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private let queue = DispatchQueue(label: "fonos.ble", qos: .userInitiated)
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var streamChar: CBCharacteristic?
    @ObservationIgnored private var statusChar: CBCharacteristic?
    @ObservationIgnored private var controlChar: CBCharacteristic?
    @ObservationIgnored private var wantsStream = false
    @ObservationIgnored private var lastSequence: UInt8?
    @ObservationIgnored private var rssiTimer: Timer?

    private static let rememberedKey = "fonos.rememberedBand"

    var rememberedBandID: UUID? {
        UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init)
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: queue,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: Public API (main thread)

    func scan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        state = .scanning
        central.scanForPeripherals(
            withServices: [FonosProtocol.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ id: UUID) {
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting(p.name ?? "Fonos band")
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    func disconnect(forget: Bool = false) {
        wantsStream = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        if forget { UserDefaults.standard.removeObject(forKey: Self.rememberedKey) }
        peripheral = nil
        state = .idle
        status = BandStatus()
        rssi = nil
    }

    func startStreaming() {
        wantsStream = true
        applyStreamState()
    }

    func stopStreaming() {
        wantsStream = false
        applyStreamState()
    }

    func send(_ command: FonosProtocol.Command, argument: UInt8? = nil) {
        guard let p = peripheral, let c = controlChar else { return }
        var bytes = [command.rawValue]
        if let argument { bytes.append(argument) }
        p.writeValue(Data(bytes), for: c, type: .withResponse)
    }

    // MARK: Private

    private func applyStreamState() {
        guard let p = peripheral, let stream = streamChar else { return }
        p.setNotifyValue(wantsStream, for: stream)
        send(wantsStream ? .startStream : .stopStream)
        lastSequence = nil
    }

    private func onMain(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    private func reconnectRemembered() {
        guard let id = rememberedBandID,
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        let name = p.name ?? "Fonos band"
        onMain { self.state = .reconnecting(name) }
        // A pending connect never times out on iOS; it completes whenever the band reappears.
        central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }
}

// MARK: - CBCentralManagerDelegate

extension BandConnection: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState: State
        switch central.state {
        case .poweredOn: newState = .idle
        case .unauthorized: newState = .unauthorized
        case .unsupported: newState = .unsupported
        default: newState = .poweredOff
        }
        onMain { self.state = newState }
        if central.state == .poweredOn { reconnectRemembered() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Fonos band"
        let item = Discovered(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        onMain {
            if let i = self.discovered.firstIndex(where: { $0.id == item.id }) {
                self.discovered[i].rssi = item.rssi
            } else {
                self.discovered.append(item)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.rememberedKey)
        peripheral.discoverServices([FonosProtocol.serviceUUID])
        let name = peripheral.name ?? "Fonos band"
        onMain {
            self.state = .connected(name)
            self.lastError = nil
            self.rssiTimer?.invalidate()
            self.rssiTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.peripheral?.readRSSI()
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onMain {
            self.lastError = error?.localizedDescription ?? "The band did not respond."
            self.state = .idle
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        streamChar = nil; statusChar = nil; controlChar = nil
        onMain {
            self.rssiTimer?.invalidate()
            self.rssi = nil
            self.status.isStreaming = false
        }
        // Unexpected drop: queue a reconnect so the band comes back on its own.
        if error != nil, peripheral.identifier == rememberedBandID {
            reconnectRemembered()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BandConnection: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == FonosProtocol.serviceUUID }) else { return }
        peripheral.discoverCharacteristics(
            [FonosProtocol.streamUUID, FonosProtocol.statusUUID, FonosProtocol.controlUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case FonosProtocol.streamUUID: streamChar = c
            case FonosProtocol.statusUUID:
                statusChar = c
                peripheral.setNotifyValue(true, for: c)
                peripheral.readValue(for: c)
            case FonosProtocol.controlUUID: controlChar = c
            default: break
            }
        }
        if wantsStream { applyStreamState() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case FonosProtocol.streamUUID:
            guard let frame = try? FrameParser.parseFrame(data) else { return }
            if let last = lastSequence, frame.sequence != last &+ 1 {
                let gap = Int(frame.sequence &- last) - 1
                onMain { self.droppedFrames += gap }
            }
            lastSequence = frame.sequence
            onFrame?(frame)
        case FonosProtocol.statusUUID:
            if let s = FrameParser.parseStatus(data) { onMain { self.status = s } }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        onMain { self.rssi = RSSI.intValue }
    }
}
