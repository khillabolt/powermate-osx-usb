import Foundation
import CoreBluetooth


    private var usbDriver: PowerMateUSBDriver?


// MARK: - Constants

let kPowermateServiceUUID = "25598CF7-4240-40A6-9910-080F19F91EBC"
let kPowermateReadCharacteristicUUID = "9cf53570-ddd9-47f3-ba63-09acefc60415"
let kPowermateLedCharacteristicUUID = "847d189e-86ee-4bd2-966f-800832b1259d"



// MARK: - Enums

enum PowerMateInputState: UInt8 {
    case press = 0x65
    case release = 0x66
    case counterClockwise = 0x67
    case clockwise = 0x68
    case pressedCounterClockwise = 0x69
    case pressedClockwise = 0x70
    case pressed1Second = 0x72
    case pressed2Second = 0x73
    case pressed3Second = 0x74
    case pressed4Second = 0x75
    case pressed5Second = 0x76
    case pressed6Second = 0x77
    
    var name: String {
        switch self {
        case .press: return "kPowermateKnobPress"
        case .release: return "kPowermateKnobRelease"
        case .counterClockwise: return "kPowermateKnobCounterClockwise"
        case .clockwise: return "kPowermateKnobClockwise"
        case .pressedCounterClockwise: return "kPowermateKnobPressedCounterClockwise"
        case .pressedClockwise: return "kPowermateKnobPressedClockwise"
        case .pressed1Second: return "kPowermateKnobPressed1Second"
        case .pressed2Second: return "kPowermateKnobPressed2Second"
        case .pressed3Second: return "kPowermateKnobPressed3Second"
        case .pressed4Second: return "kPowermateKnobPressed4Second"
        case .pressed5Second: return "kPowermateKnobPressed5Second"
        case .pressed6Second: return "kPowermateKnobPressed6Second"
        }
    }
}

// MARK: - Driver Class

@Observable
class PowerMateDriver: NSObject {
    var isConnected: Bool = false
    var errorReason: String = ""
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        usbDriver = PowerMateUSBDriver()
        usbDriver?.start()
        
        // Register for distributed notifications for LED control
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(ledNotificationObserver(_:)),
            name: kPowermateLEDNotification,
            object: nil
        )
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - Scanning
    
    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        let serviceUUID = CBUUID(string: kPowermateServiceUUID)
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
    
    // MARK: - Event Processing
    
    private func process(value: UInt8) {
        guard let state = PowerMateInputState(rawValue: value) else {
            print("Unknown PowerMate state: \(value)")
            return
        }
        
        // Broadcast event system-wide
        DistributedNotificationCenter.default().postNotificationName(
            kPowermateKnobNotification,
            object: state.name,
            userInfo: nil,
            deliverImmediately: true
        )
        print("Broadcasted: \(state.name)")
    }
    
    // MARK: - LED Control
    
    @objc private func ledNotificationObserver(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: Any],
              let function = userInfo["fn"] as? String else {
            print("Invalid LED notification")
            return
        }
        
        switch function {
        case kPowermateLEDOn:
            setLedOn()
        case kPowermateLEDOff:
            setLedOff()
        case kPowermateLEDFlash:
            if let level = userInfo["level"] as? Int {
                if level == 32 {
                    quickBlinkLed()
                } else {
                    blinkLedAtSpeed(speed: level)
                }
            }
        case kPowermateLEDLevel:
            if let level = userInfo["level"] as? Float {
                setLedBrightness(intensity: level)
            }
        default:
            print("Unknown LED command: \(function)")
        }
    }
    
    private func setLedRawValue(_ brightness: UInt8) {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else { return }
        
        var brightnessVal = brightness
        let data = Data(bytes: &brightnessVal, count: 1)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    func setLedBrightness(intensity: Float) {
        var brightness: UInt8 = UInt8(((0xbf - 0xa1) * intensity) + 0xa1)
        if intensity <= 0 { brightness = 0x80 }
        if intensity >= 1 { brightness = 0xbf }
        setLedRawValue(brightness)
    }
    
    func setLedOn() {
        setLedRawValue(0x81)
    }
    
    func setLedOff() {
        setLedRawValue(0x80)
    }
    
    func quickBlinkLed() {
        setLedRawValue(0xa0)
    }
    
    func blinkLedAtSpeed(speed: Int) {
        let clampedSpeed = min(speed, 31)
        setLedRawValue(UInt8(0xdf - clampedSpeed))
    }
}

// MARK: - CBCentralManagerDelegate

extension PowerMateDriver: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            errorReason = ""
            startScan()
        case .poweredOff:
            errorReason = "Bluetooth is currently powered off."
            isConnected = false
        case .unauthorized:
            errorReason = "The app is not authorized to use Bluetooth Low Energy."
            isConnected = false
        case .unsupported:
            errorReason = "The platform/hardware doesn't support Bluetooth Low Energy."
            isConnected = false
        default:
            errorReason = "Bluetooth state is unknown."
            isConnected = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered PowerMate!")
        self.peripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to PowerMate")
        peripheral.delegate = self
        self.peripheral = peripheral
        
        let serviceUUID = CBUUID(string: kPowermateServiceUUID)
        peripheral.discoverServices([serviceUUID])
        centralManager.stopScan()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from PowerMate")
        isConnected = false
        self.peripheral = nil
        self.writeCharacteristic = nil
        startScan()
    }
}

// MARK: - CBPeripheralDelegate

extension PowerMateDriver: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid.uuidString == kPowermateServiceUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid.uuidString.lowercased() == kPowermateReadCharacteristicUUID.lowercased() {
                if !characteristic.isNotifying {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            
            if characteristic.uuid.uuidString.lowercased() == kPowermateLedCharacteristicUUID.lowercased() {
                writeCharacteristic = characteristic
                setLedOff() // Default to off
            }
        }
        
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let value = data[0]
        process(value: value)
    }
}
