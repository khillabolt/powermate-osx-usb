import Foundation
import SwiftUI

@Observable
class PowerMateViewModel {
    var driver: PowerMateDriver
    
    init() {
        self.driver = PowerMateDriver()
    }
    
    var statusText: String {
        if driver.isConnected {
            return "Connected"
        } else if !driver.errorReason.isEmpty {
            return driver.errorReason
        } else {
            return "Scanning..."
        }
    }
    
    var icon: String {
        return driver.isConnected ? "dial.max.fill" : "dial.min"
    }
    
    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
