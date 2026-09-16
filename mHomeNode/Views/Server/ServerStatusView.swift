import SwiftUI

public struct ServerStatusView: View {
    @State private var serverConfig = ServerConfig()
    @State private var connectionStatus: ServerConnectionStatus = .disconnected
    @State private var serverStatus: ServerStatus?
    @State private var isChecking = false
    private let client: HomeNodeServerClientProtocol = MockHomeNodeServerClient()

    public var body: some View {
        NavigationStack {
            Form {
                Section("Connection Settings") {
                    TextField("Server Host", text: $serverConfig.host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Stepper("Port: \(serverConfig.port)", value: $serverConfig.port, in: 1...65535)

                    Toggle("Use TLS (HTTPS)", isOn: $serverConfig.useTLS)

                    SecureField("API Key (Optional)", text: Binding(
                        get: { serverConfig.apiKey ?? "" },
                        set: { serverConfig.apiKey = $0.isEmpty ? nil : $0 }
                    ))

                    Button {
                        checkConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isChecking {
                                ProgressView()
                            } else {
                                Image(systemName: "network")
                            }
                        }
                    }
                    .disabled(isChecking)
                }

                Section("Server Overview") {
                    LabeledContent("Status", value: connectionStatus.rawValue)
                    if let status = serverStatus {
                        LabeledContent("Server Version", value: status.version)
                        LabeledContent("Active Matter Nodes", value: "\(status.activeMatterNodes)")
                        LabeledContent("BLE Gateways", value: "\(status.activeBLEGateways)")
                        LabeledContent("Uptime", value: "\(status.uptimeSeconds / 60) min")
                    }
                }

                Section("HomeNode Architecture") {
                    Text("The iPhone app serves as the **Mobile Scout** and **Matter Commissioner** for HomeNode. Long-running automation and LAN discovery are handled by the Rust-based HomeNode Server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("HomeNode Server")
        }
    }

    private func checkConnection() {
        isChecking = true
        connectionStatus = .connecting

        Task {
            do {
                let status = try await client.checkHealth(config: serverConfig)
                await MainActor.run {
                    self.serverStatus = status
                    self.connectionStatus = .connected
                    self.isChecking = false
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = .error
                    self.isChecking = false
                }
            }
        }
    }
}
