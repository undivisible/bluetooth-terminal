import SwiftUI

struct TerminalView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @State private var inputText: String = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var hexMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bluetooth.connectedDevice?.name ?? "Device")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white)
                    
                    Text("Connected")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                Button("Disconnect") {
                    bluetooth.disconnect()
                }
                .font(.system(size: 13))
                .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .bottom)
            
            // Output Area
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(bluetooth.messages) { msg in
                            HStack(alignment: .top, spacing: 12) {
                                Text(timestamp(msg.timestamp))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 60, alignment: .leading)
                                
                                Text(msg.text)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(color(for: msg.type))
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .id(msg.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .background(Color.black)
                .onChange(of: bluetooth.messages.count) {
                    if let last = bluetooth.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            HStack(spacing: 12) {
                TextField("Enter command", text: $inputText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(0)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Text("Send")
                        .font(.system(size: 13))
                        .foregroundColor(inputText.isEmpty ? .white.opacity(0.2) : .white)
                }
                .disabled(inputText.isEmpty)
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.black)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.1)), alignment: .top)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showHistory) {
            CommandHistoryView(history: bluetooth.getHistory(), onSelect: { command in
                inputText = command
                showHistory = false
            })
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(bluetooth: bluetooth)
        }
    }
    
    func sendMessage() {
        guard !inputText.isEmpty else { return }
        bluetooth.sendMessage(inputText)
        inputText = ""
    }
    
    func color(for type: BluetoothManager.TerminalMessage.MessageType) -> Color {
        switch type {
        case .tx: return .white.opacity(0.6)
        case .rx: return .white
        case .info: return .white.opacity(0.4)
        case .error: return .white.opacity(0.8)
        }
    }
    
    func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// Helper for top corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Command History View
struct CommandHistoryView: View {
    let history: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if history.isEmpty {
                    VStack {
                        Text("No History")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.3))
                    }
                } else {
                    List {
                        ForEach(history.indices, id: \.self) { index in
                            Button {
                                onSelect(history[index])
                            } label: {
                                Text(history[index])
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                List {
                    Section {
                        Button {
                            bluetooth.clearMessages()
                            dismiss()
                        } label: {
                            Text("Clear Messages")
                                .foregroundColor(.white)
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    Section {
                        HStack {
                            Text("Version")
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("1.0")
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
