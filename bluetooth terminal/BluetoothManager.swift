import Foundation
import CoreBluetooth
import Combine

// Bluetooth Manager for handling BLE operations
// Supports standard Nordic UART Service
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Published State
    
    @Published var isBluetoothEnabled = false
    @Published var isScanning = false
    @Published var discoveredDevices: [BluetoothDevice] = []
    @Published var connectedDevice: BluetoothDevice?
    @Published var messages: [TerminalMessage] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectionQuality: ConnectionQuality = .unknown
    @Published var bytesSent: Int = 0
    @Published var bytesReceived: Int = 0
    
    // MARK: - Types
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }
    
    enum ConnectionQuality {
        case unknown
        case excellent
        case good
        case fair
        case poor
        
        init(rssi: Int) {
            switch rssi {
            case -50...0: self = .excellent
            case -70 ..< -50: self = .good
            case -85 ..< -70: self = .fair
            case ..<(-85): self = .poor
            default: self = .unknown
            }
        }
        
        var bars: Int {
            switch self {
            case .excellent: return 4
            case .good: return 3
            case .fair: return 2
            case .poor: return 1
            case .unknown: return 0
            }
        }
    }
    
    struct BluetoothDevice: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral
        
        static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    struct TerminalMessage: Identifiable {
        let id = UUID()
        let text: String
        let type: MessageType
        let timestamp = Date()
        
        enum MessageType {
            case tx     // Transmitted
            case rx     // Received
            case info   // System info
            case error  // Error message
        }
    }
    
    // MARK: - UUIDs
    
    // Nordic UART Service (NUS)
    private let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let uartRxCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write
    private let uartTxCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify
    
    // JDY-23 Specific (Alternate)
    private let jdyServiceUUID  = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    private let jdyCharUUID     = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB") // Write+Notify
    
    // MARK: - Properties
    
    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var rssiTimer: Timer?
    private var commandHistory: [String] = []
    private let maxHistorySize = 50
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public API
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("⚠️ Cannot scan - Bluetooth state: \(centralManager.state.rawValue)")
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll()
        
        print("🔍 Starting BLE scan...")
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        addMessage("Scanning for devices...", type: .info)
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        addMessage("Stopped scanning", type: .info)
    }
    
    func connect(to device: BluetoothDevice) {
        stopScanning()
        connectionState = .connecting
        activePeripheral = device.peripheral
        activePeripheral?.delegate = self
        
        centralManager.connect(device.peripheral, options: nil)
        addMessage("Connecting to \(device.name)...", type: .info)
    }
    
    func disconnect() {
        if let peripheral = activePeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            // Cleanup happens in didDisconnect
        }
        stopRSSIMonitoring()
    }
    
    func clearMessages() {
        messages.removeAll()
        addMessage("Messages cleared", type: .info)
    }
    
    func exportMessages() -> String {
        messages.map { msg in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let time = formatter.string(from: msg.timestamp)
            let prefix = prefixForType(msg.type)
            return "[\(time)] \(prefix) \(msg.text)"
        }.joined(separator: "\n")
    }
    
    func addToHistory(_ command: String) {
        commandHistory.insert(command, at: 0)
        if commandHistory.count > maxHistorySize {
            commandHistory.removeLast()
        }
    }
    
    func getHistory() -> [String] {
        return commandHistory
    }
    
    private func prefixForType(_ type: TerminalMessage.MessageType) -> String {
        switch type {
        case .tx: return "TX:"
        case .rx: return "RX:"
        case .info: return "INFO:"
        case .error: return "ERROR:"
        }
    }
    
    private func startRSSIMonitoring() {
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.activePeripheral?.readRSSI()
        }
    }
    
    private func stopRSSIMonitoring() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        connectionQuality = .unknown
    }
    
    func sendMessage(_ text: String) {
        guard let peripheral = activePeripheral, 
              let char = rxCharacteristic ?? txCharacteristic
        else {
            addMessage("Not ready to send", type: .error)
            return
        }
        
        let stringToSend = text.hasSuffix("\n") ? text : text + "\r\n"
        
        if let data = stringToSend.data(using: .utf8) {
            let writeType: CBCharacteristicWriteType = 
                (char.properties.contains(.writeWithoutResponse)) ? .withoutResponse : .withResponse
            
            peripheral.writeValue(data, for: char, type: writeType)
            bytesSent += data.count
            addMessage(text.trimmingCharacters(in: .whitespacesAndNewlines), type: .tx)
            addToHistory(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    
    func sendData(_ data: Data) {
        guard let peripheral = activePeripheral, 
              let char = rxCharacteristic ?? txCharacteristic
        else {
            addMessage("Not ready to send", type: .error)
            return
        }
        
        let writeType: CBCharacteristicWriteType = 
            (char.properties.contains(.writeWithoutResponse)) ? .withoutResponse : .withResponse
        
        peripheral.writeValue(data, for: char, type: writeType)
        bytesSent += data.count
        addMessage("Sent \(data.count) bytes (hex: \(data.map { String(format: "%02X", $0) }.joined()))", type: .tx)
    }
    
    // MARK: - Helper Methods
    
    private func addMessage(_ text: String, type: TerminalMessage.MessageType) {
        let message = TerminalMessage(text: text, type: type)
        DispatchQueue.main.async {
            self.messages.append(message)
            // Limit messages to prevent memory issues
            if self.messages.count > 500 {
                self.messages.removeFirst(100)
            }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothEnabled = central.state == .poweredOn
        print("🔵 Bluetooth state: \(central.state.rawValue) - Enabled: \(isBluetoothEnabled)")
        
        if central.state == .poweredOn {
            addMessage("Bluetooth ready", type: .info)
        } else {
            addMessage("Bluetooth not ready", type: .error)
            isScanning = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        
        print("📱 Found device: \(name) (\(RSSI) dBm)")
        
        // Optimize: Only update if RSSI changed significantly or new device
        if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            let oldRSSI = discoveredDevices[existingIndex].rssi
            if abs(oldRSSI - RSSI.intValue) > 5 { // Only update if changed by more than 5 dBm
                discoveredDevices[existingIndex] = BluetoothDevice(
                    id: peripheral.identifier,
                    name: name,
                    rssi: RSSI.intValue,
                    peripheral: peripheral
                )
                print("🔄 Updated device: \(name)")
            }
        } else {
            let device = BluetoothDevice(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral
            )
            discoveredDevices.append(device)
            print("➕ Added device: \(name) - Total: \(discoveredDevices.count)")
        }
        
        // Sort only if needed (limit updates)
        if discoveredDevices.count < 20 || discoveredDevices.count % 5 == 0 {
            discoveredDevices.sort { $0.rssi > $1.rssi }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        connectedDevice = discoveredDevices.first(where: { $0.id == peripheral.identifier })
        addMessage("Connected to \(peripheral.name ?? "Unknown")", type: .info)
        
        bytesSent = 0
        bytesReceived = 0
        startRSSIMonitoring()
        
        peripheral.discoverServices([uartServiceUUID, jdyServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        addMessage("Failed to connect: \(error?.localizedDescription ?? "Unknown error")", type: .error)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedDevice = nil
        activePeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        stopRSSIMonitoring()
        
        if let error = error {
            addMessage("Disconnected with error: \(error.localizedDescription)", type: .error)
        } else {
            addMessage("Disconnected", type: .info)
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            addMessage("Service discovery error: \(error.localizedDescription)", type: .error)
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == uartServiceUUID || service.uuid == jdyServiceUUID {
                addMessage("Found UART Service", type: .info)
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            addMessage("Char discovery error: \(error.localizedDescription)", type: .error)
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            // Nordic UART Service
            if char.uuid == uartTxCharUUID {
                peripheral.setNotifyValue(true, for: char)
                addMessage("Ready to receive (NUS)", type: .info)
            }
            if char.uuid == uartRxCharUUID {
                rxCharacteristic = char
                addMessage("Ready to write (NUS)", type: .info)
            }
            
            // JDY-23 (Single characteristic for RX/TX)
            if char.uuid == jdyCharUUID {
                rxCharacteristic = char 
                txCharacteristic = char // Use same for both
                peripheral.setNotifyValue(true, for: char)
                addMessage("Ready (JDY-23)", type: .info)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            addMessage("Read error: \(error.localizedDescription)", type: .error)
            return
        }
        
        if let data = characteristic.value {
            bytesReceived += data.count
            if let string = String(data: data, encoding: .utf8) {
                addMessage(string, type: .rx)
            } else {
                let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                addMessage("HEX: \(hex)", type: .rx)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil {
            DispatchQueue.main.async {
                self.connectionQuality = ConnectionQuality(rssi: RSSI.intValue)
            }
        }
    }
}
