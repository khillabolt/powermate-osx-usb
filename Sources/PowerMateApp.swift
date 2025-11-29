import SwiftUI

@main
struct PowerMateApp: App {
    @State private var viewModel = PowerMateViewModel()
    
    var body: some Scene {
        MenuBarExtra(viewModel.icon, systemImage: viewModel.icon) {
            Text("PowerMate Driver")
                .font(.headline)
            
            Divider()
            
            Text(viewModel.statusText)
                .foregroundColor(viewModel.driver.isConnected ? .green : .gray)
            
            Divider()
            
            Button("Quit") {
                viewModel.quit()
            }
            .keyboardShortcut("q")
        }
    }
}
