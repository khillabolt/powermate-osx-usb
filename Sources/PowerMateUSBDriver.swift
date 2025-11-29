// PowerMateUSBDriver.swift
// USB HID driver for Griffin PowerMate (USB mode)

import Foundation
import IOKit.hid
import IOKit
import AppKit
import OSLog
import os.log

// Shared notification names (same as Bluetooth driver)
let kPowermateKnobNotification = Notification.Name("kPowermateKnobNotification")
let kPowermateLEDNotification = Notification.Name("kPowermateLEDNotification")

// LED command constants (same as Bluetooth driver)
let kPowermateLEDOn = "kPowermateLEDOn"
let kPowermateLEDOff = "kPowermateLEDOff"
let kPowermateLEDFlash = "kPowermateLEDFlash"
let kPowermateLEDLevel = "kPowermateLEDLevel"

class PowerMateUSBDriver: NSObject {
    private var manager: IOHIDManager!
    private var device: IOHIDDevice?
    private let vendorID: Int = 0x077D
    private let productID: Int = 0x0410
    private let queue = DispatchQueue(label: "PowerMateUSBDriverQueue")
    private let logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.static-pulsar.powermate",
                               category: "PowerMateUSBDriver")
    
    private func log(_ type: OSLogType, _ message: String) {
        #if DEBUG
        os_log("%{public}@", log: logger, type: type, message)
        #endif
    }

    override init() {
        super.init()
        setupManager()
    }

    private func setupManager() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        log(.debug, "Created IOHIDManager instance")
        let matching: [String: Any] = [kIOHIDVendorIDKey as String: vendorID,
                                      kIOHIDProductIDKey as String: productID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        log(.debug, "Configured matching dictionary (vendor=\(vendorID), product=\(productID))")
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let deviceCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let mySelf = Unmanaged<PowerMateUSBDriver>.fromOpaque(context!).takeUnretainedValue()
            mySelf.deviceConnected(device)
        }
        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let mySelf = Unmanaged<PowerMateUSBDriver>.fromOpaque(context!).takeUnretainedValue()
            mySelf.deviceDisconnected(device)
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceCallback, selfPointer)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, selfPointer)
        log(.debug, "Registered device callbacks")
    }

    func start() {
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        log(.debug, "Scheduled IOHIDManager on current run loop")
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            log(.debug, "IOHIDManager opened successfully")
        } else {
            log(.error, "IOHIDManagerOpen failed with code \(openResult)")
        }
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        self.device = device
        log(.info, "PowerMate connected: \(describe(device: device))")
        // Register input report callback
        let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
            let mySelf = Unmanaged<PowerMateUSBDriver>.fromOpaque(context!).takeUnretainedValue()
            mySelf.handleInputReport(report: report, length: reportLength)
        }
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, reportCallback, selfPtr)
        log(.debug, "Registered input report callback (buffer=64 bytes)")
        // Start receiving notifications
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        log(.debug, "Scheduled device on run loop")
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        if self.device === device {
            self.device = nil
        }
        log(.info, "PowerMate disconnected")
    }

    private func handleInputReport(report: UnsafeMutablePointer<UInt8>?, length: CFIndex) {
        guard let report = report, length >= 2 else {
            log(.debug, "Received short or nil report (length=\(length))")
            return
        }
        let bytesToLog = min(Int(length), 8)
        log(.debug, "Report (\(length) bytes) sample=\(hexSnippet(from: report, count: bytesToLog))")
        // Byte 0: button state, Byte 1: rotation delta (signed)
        let button = report[0]
        let delta = Int8(bitPattern: report[1])
        log(.debug, "Parsed report button=\(button) delta=\(delta)")
        // Map to notifications similar to Bluetooth driver
        if button & 0x01 != 0 {
            DistributedNotificationCenter.default().postNotificationName(kPowermateKnobNotification, object: "kPowermateKnobPress", userInfo: nil, deliverImmediately: true)
        } else {
            DistributedNotificationCenter.default().postNotificationName(kPowermateKnobNotification, object: "kPowermateKnobRelease", userInfo: nil, deliverImmediately: true)
        }
        // Rotation: positive = clockwise, negative = counter‑clockwise
        if delta != 0 {
            let name = delta > 0 ? "kPowermateKnobClockwise" : "kPowermateKnobCounterClockwise"
            DistributedNotificationCenter.default().postNotificationName(kPowermateKnobNotification, object: name, userInfo: nil, deliverImmediately: true)
        }
    }

    // MARK: - LED Control (vendor‑specific control transfer)
    private func sendControl(command: UInt8, value: UInt16 = 0) {
        // Stub implementation: no actual USB control transfer.
        // This placeholder avoids compile errors related to IOKit USB structures.
        // Future implementation can use IOUSBDeviceInterface as needed.
    }

    func setLED(brightness: UInt8) { // 0x00‑0xFF maps to SET_STATIC_BRIGHTNESS (0x01)
        sendControl(command: 0x01, value: UInt16(brightness))
    }

    func setLEDPulse(mode: UInt8, speed: UInt8) {
        // mode 0x02 = asleep, 0x03 = awake, 0x04 = pulse mode
        // For simplicity we only implement pulse mode here.
        sendControl(command: 0x04, value: UInt16(speed))
    }

    // MARK: - Debug helpers
    private func describe(device: IOHIDDevice) -> String {
        var details: [String] = []
        if let product = property(kIOHIDProductKey as CFString, as: String.self, for: device) {
            details.append("product=\(product)")
        }
        if let vendorNumber = property(kIOHIDVendorIDKey as CFString, as: NSNumber.self, for: device) {
            details.append("vendorID=0x\(String(format: "%04X", vendorNumber.intValue))")
        }
        if let productNumber = property(kIOHIDProductIDKey as CFString, as: NSNumber.self, for: device) {
            details.append("productID=0x\(String(format: "%04X", productNumber.intValue))")
        }
        if let serial = property(kIOHIDSerialNumberKey as CFString, as: String.self, for: device) {
            details.append("serial=\(serial)")
        }
        return details.isEmpty ? "<unknown device>" : details.joined(separator: ", ")
    }

    private func property<T>(_ key: CFString, as type: T.Type, for device: IOHIDDevice) -> T? {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
        return value as? T
    }

    private func hexSnippet(from pointer: UnsafeMutablePointer<UInt8>, count: Int) -> String {
        guard count > 0 else { return "" }
        return (0..<count)
            .map { String(format: "%02X", pointer[$0]) }
            .joined(separator: " ")
    }
}
