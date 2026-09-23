import Foundation
import CoreBluetooth
import Combine

/// iOS counterpart to the Android BleMeshManager. Same service/characteristic
/// UUIDs, same JSON message format, same shared-passphrase encryption --
/// the two apps are meant to actually talk to each other over BLE, not just
/// separately exist.
///
/// FOREGROUND ONLY, DELIBERATELY. No background modes are declared. iOS
/// restricts backgrounded apps' BLE so aggressively that two backgrounded
/// iPhones essentially can't find each other -- adding background
/// capability here would be decoration, not function. Keep this app open
/// on screen while testing.
final class BleMeshManager: NSObject, ObservableObject {

    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    @Published var messages: [MeshMessage] = []
    @Published var peerCount: Int = 0
    @Published var isActive: Bool = false {
        didSet { isActive ? start() : stop() }
    }

    var localNickname: String = "Anonymous"

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var mutableCharacteristic: CBMutableCharacteristic?
    private var subscribedCentrals = Set<CBCentral>()

    // Single outgoing connection at a time -- mirrors the Android app's
    // "one peer at a time" design, same rationale: keeping several
    // concurrent GATT connections' write queues straight is real added
    // complexity, not a quick upgrade.
    private var connectedPeripheral: CBPeripheral?
    private var writableCharacteristic: CBCharacteristic?
    private var pendingOutgoing: [MeshMessage] = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: - Public control

    private func start() {
        if peripheralManager.state == .poweredOn {
            setupServiceIfNeeded()
            startAdvertising()
        }
        if centralManager.state == .poweredOn {
            startScanning()
        }
    }

    private func stop() {
        centralManager.stopScan()
        peripheralManager.stopAdvertising()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writableCharacteristic = nil
        pendingOutgoing = []
    }

    func sendMessage(_ text: String) {
        let message = MeshMessage(senderNickname: localNickname, body: text)
        messages.append(message)
        // No further action needed here -- the message now lives in
        // `messages` and gets pushed to the next peer this device
        // connects to or is subscribed by, via the exact same code path
        // as a relayed message. See pushRelayable(to:).
    }

    // MARK: - Relay source of truth

    private func relayableMessages() -> [MeshMessage] {
        messages.filter { $0.ttl > 0 }
    }

    private func handleIncomingData(_ data: Data) {
        guard let encryptedString = String(data: data, encoding: .utf8) else { return }
        let decrypted = SimpleCrypto.decrypt(encryptedString)
        guard !decrypted.isEmpty, let jsonData = decrypted.data(using: .utf8) else { return }
        guard var incoming = MeshMessage.from(jsonData: jsonData) else { return }

        if messages.contains(where: { $0.id == incoming.id }) { return } // already have it

        incoming.ttl -= 1
        incoming.hopCount += 1
        messages.append(incoming)
        // Storing it (even at ttl 0) means it's still shown locally;
        // relayableMessages() filters ttl<=0 out of what gets pushed onward.
    }

    private func encode(_ message: MeshMessage) -> Data? {
        guard let jsonData = message.toJSONData(),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }
        let encrypted = SimpleCrypto.encrypt(jsonString)
        guard !encrypted.isEmpty else { return nil }
        return encrypted.data(using: .utf8)
    }

    // MARK: - Peripheral (server) role

    private func setupServiceIfNeeded() {
        guard mutableCharacteristic == nil else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.charUUID,
            properties: [.notify, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)
        mutableCharacteristic = characteristic
    }

    private func startAdvertising() {
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ])
    }

    private func pushRelayable(to central: CBCentral) {
        guard let characteristic = mutableCharacteristic else { return }
        for message in relayableMessages() {
            guard let data = encode(message) else { continue }
            peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: [central])
        }
    }

    // MARK: - Central (client) role

    private func startScanning() {
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    private func writeNextPending() {
        guard let peripheral = connectedPeripheral, let characteristic = writableCharacteristic else { return }
        guard !pendingOutgoing.isEmpty else {
            // Done pushing our side; give the peer a moment to notify us
            // back, then move on. A fixed short delay is simple and good
            // enough for a foreground-only test app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.centralManager.cancelPeripheralConnection(peripheral)
            }
            return
        }
        let next = pendingOutgoing.removeFirst()
        guard let data = encode(next) else { writeNextPending(); return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate

extension BleMeshManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, isActive {
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard connectedPeripheral == nil else { return } // one peer at a time
        connectedPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        writableCharacteristic = nil
        pendingOutgoing = []
        if isActive { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        if isActive { startScanning() }
    }
}

// MARK: - CBPeripheralDelegate (when we're the central/client)

extension BleMeshManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.charUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.charUUID }) else {
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        writableCharacteristic = characteristic
        // CoreBluetooth handles the CCCD subscribe handshake for us here --
        // unlike Android, no manual descriptor write needed on this side.
        peripheral.setNotifyValue(true, for: characteristic)
        pendingOutgoing = relayableMessages()
        writeNextPending()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        writeNextPending()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.charUUID, let data = characteristic.value else { return }
        handleIncomingData(data)
    }
}

// MARK: - CBPeripheralManagerDelegate (when we're the peripheral/server)

extension BleMeshManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, isActive {
            setupServiceIfNeeded()
            startAdvertising()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                handleIncomingData(value)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                            didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.insert(central)
        peerCount = subscribedCentrals.count
        pushRelayable(to: central)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                            didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.remove(central)
        peerCount = subscribedCentrals.count
    }
}
