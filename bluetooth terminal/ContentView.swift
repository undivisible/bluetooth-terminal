import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var showFilterOptions = false
    @State private var signalFilter: SignalStrength = .all
    
    enum SignalStrength: String, CaseIterable {
        case all = "All Devices"
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
    }
    
    var filteredDevices: [BluetoothManager.BluetoothDevice] {
        switch signalFilter {
        case .all:
            return bluetooth.discoveredDevices
        case .excellent:
            return bluetooth.discoveredDevices.filter { $0.rssi > -50 }
        case .good:
            return bluetooth.discoveredDevices.filter { $0.rssi > -70 }
        case .fair:
            return bluetooth.discoveredDevices.filter { $0.rssi > -85 }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Content
                if bluetooth.connectionState == .connected {
                    TerminalView(bluetooth: bluetooth)
                        .transition(.opacity)
                } else {
                    scanView
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: bluetooth.connectionState)
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Auto-start scanning when Bluetooth is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !bluetooth.isScanning {
                    bluetooth.startScanning()
                }
            }
        }
        .onChange(of: bluetooth.isBluetoothEnabled) {
            // Start scanning when Bluetooth becomes enabled
            if bluetooth.isBluetoothEnabled && !bluetooth.isScanning {
                bluetooth.startScanning()
            }
        }
    }
    
    var scanView: some View {
        VStack(spacing: 0) {
            // Device List
            if bluetooth.discoveredDevices.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    
                    if !bluetooth.isBluetoothEnabled {
                        Text("Bluetooth Off")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.3))
                    } else if bluetooth.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.3)))
                            .scaleEffect(0.8)
                        Text("Scanning")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.3))
                    } else {
                        Text("No Devices")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    
                    Spacer()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(bluetooth.discoveredDevices) { device in
                            DeviceRow(device: device) {
                                bluetooth.connect(to: device)
                            }
                            
                            if device.id != bluetooth.discoveredDevices.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
    }
    
    func toggleScan() {
        if bluetooth.isScanning {
            bluetooth.stopScanning()
        } else {
            bluetooth.startScanning()
        }
    }
}