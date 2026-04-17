import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject  private var service: UniswapService
    var onDismiss: (() -> Void)? = nil
    @State private var draftWalletAddress: String
    @State private var draftInfuraAPIKey: String
    @State private var draftEnabledChainIDs: Set<String>
    @State private var draftRefreshIntervalMinutes: Int
    @State private var draftRPCCreditsPerSecondBudget: Int
    @State private var draftV4LogChunkSize: Int
    @State private var draftV4LogMaxConcurrentRequests: Int
    @State private var draftV4BootstrapMaxChunksPerRefresh: Int
    @State private var draftLaunchAtLogin: Bool
    @State private var draftFlashOnValueChange: Bool

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        let s = AppSettings.shared
        _draftWalletAddress = State(initialValue: s.walletAddress)
        _draftInfuraAPIKey = State(initialValue: s.infuraAPIKey)
        _draftEnabledChainIDs = State(initialValue: s.enabledChainIDs)
        _draftRefreshIntervalMinutes = State(initialValue: s.refreshIntervalMinutes)
        _draftRPCCreditsPerSecondBudget = State(initialValue: s.rpcCreditsPerSecondBudget)
        _draftV4LogChunkSize = State(initialValue: s.v4LogChunkSize)
        _draftV4LogMaxConcurrentRequests = State(initialValue: s.v4LogMaxConcurrentRequests)
        _draftV4BootstrapMaxChunksPerRefresh = State(initialValue: s.v4BootstrapMaxChunksPerRefresh)
        _draftLaunchAtLogin = State(initialValue: s.launchAtLogin)
        _draftFlashOnValueChange = State(initialValue: s.flashOnValueChange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsSection("Infura Configuration") {
                        VStack(spacing: 0) {
                            fieldRow(
                                label: "Wallet Address",
                                info: "Address to inspect for Uniswap v3/v4 NFT liquidity positions.",
                                placeholder: "0x…",
                                text: $draftWalletAddress
                            )
                            Divider().opacity(0.35).padding(.leading, 14)
                            fieldRow(
                                label: "Infura API Key",
                                info: "Only the API key is needed. RPC URLs are generated per enabled chain.",
                                placeholder: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
                                text: $draftInfuraAPIKey
                            )
                            Divider().opacity(0.35).padding(.leading, 14)
                            VStack(alignment: .leading, spacing: 8) {
                                infoTitle("Enabled Networks", info: "Select which Infura-backed EVM chains to scan.")
                                ForEach(SupportedChain.all) { chain in
                                    HStack(spacing: 10) {
                                        HStack(spacing: 8) {
                                            ChainIconView(chain: chain, size: 16)
                                            Text(chain.displayName)
                                                .font(.system(size: 12))
                                        }
                                        Spacer(minLength: 0)
                                        Toggle("", isOn: Binding(
                                            get: { draftEnabledChainIDs.contains(chain.id) },
                                            set: { enabled in
                                                if enabled { draftEnabledChainIDs.insert(chain.id) }
                                                else { draftEnabledChainIDs.remove(chain.id) }
                                            }
                                        ))
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 12)
                    }

                    settingsSection("Performance & RPC") {
                        VStack(spacing: 0) {
                            settingRow(
                                label: "Refresh Interval",
                                info: "Automatic refresh cadence in minutes."
                            ) {
                                Stepper(value: $draftRefreshIntervalMinutes, in: 1...120) {
                                    Text("\(draftRefreshIntervalMinutes) min")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .frame(width: 140, alignment: .trailing)
                            }
                            Divider().opacity(0.35).padding(.leading, 14)
                            settingRow(
                                label: "RPC Credit Budget",
                                info: "Max client-side request pacing budget (credits per second)."
                            ) {
                                Stepper(value: $draftRPCCreditsPerSecondBudget, in: 50...5_000, step: 25) {
                                    Text("\(draftRPCCreditsPerSecondBudget) cps")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .frame(width: 140, alignment: .trailing)
                            }
                            Divider().opacity(0.35).padding(.leading, 14)
                            settingRow(
                                label: "v4 Log Chunk Size",
                                info: "Blocks per eth_getLogs request during v4 ownership discovery."
                            ) {
                                Stepper(value: $draftV4LogChunkSize, in: 1_000...50_000, step: 1_000) {
                                    Text("\(draftV4LogChunkSize)")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .frame(width: 140, alignment: .trailing)
                            }
                            Divider().opacity(0.35).padding(.leading, 14)
                            settingRow(
                                label: "v4 Log Concurrency",
                                info: "Parallel eth_getLogs requests during v4 scanning."
                            ) {
                                Stepper(value: $draftV4LogMaxConcurrentRequests, in: 1...8) {
                                    Text("\(draftV4LogMaxConcurrentRequests)")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .frame(width: 140, alignment: .trailing)
                            }
                            Divider().opacity(0.35).padding(.leading, 14)
                            settingRow(
                                label: "Bootstrap Chunks / Refresh",
                                info: "Max v4 history chunks scanned in one refresh cycle."
                            ) {
                                Stepper(value: $draftV4BootstrapMaxChunksPerRefresh, in: 5...200, step: 5) {
                                    Text("\(draftV4BootstrapMaxChunksPerRefresh)")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .frame(width: 140, alignment: .trailing)
                            }
                            Divider().opacity(0.35).padding(.leading, 14)
                            HStack {
                                Spacer()
                                Button("Reset Performance Defaults") {
                                    draftRefreshIntervalMinutes = 10
                                    draftRPCCreditsPerSecondBudget = 400
                                    draftV4LogChunkSize = 12_000
                                    draftV4LogMaxConcurrentRequests = 2
                                    draftV4BootstrapMaxChunksPerRefresh = 80
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .glassCard(cornerRadius: 12)
                    }

                    settingsSection("General") {
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Launch at Login")
                                        .font(.system(size: 13))
                                    Text("Open automatically when you log in")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { draftLaunchAtLogin },
                                    set: { draftLaunchAtLogin = $0 }
                                ))
                                .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider().opacity(0.35).padding(.leading, 14)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Flash on Value Change")
                                        .font(.system(size: 13))
                                    Text("Briefly animates the menu bar icon when your total unclaimed fees change after a refresh")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $draftFlashOnValueChange)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            if let err = settings.loginItemError {
                                Divider().opacity(0.35).padding(.leading, 14)
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .glassCard(cornerRadius: 12)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.35)

            HStack {
                Spacer()
                Button("Save & Refresh") {
                    settings.walletAddress = draftWalletAddress
                    settings.infuraAPIKey = draftInfuraAPIKey
                    settings.enabledChainIDs = draftEnabledChainIDs
                    settings.refreshIntervalMinutes = draftRefreshIntervalMinutes
                    settings.rpcCreditsPerSecondBudget = draftRPCCreditsPerSecondBudget
                    settings.v4LogChunkSize = draftV4LogChunkSize
                    settings.v4LogMaxConcurrentRequests = draftV4LogMaxConcurrentRequests
                    settings.v4BootstrapMaxChunksPerRefresh = draftV4BootstrapMaxChunksPerRefresh
                    settings.flashOnValueChange = draftFlashOnValueChange
                    if settings.launchAtLogin != draftLaunchAtLogin {
                        Task { await settings.setLaunchAtLogin(draftLaunchAtLogin) }
                    }
                    service.refresh()
                    onDismiss?()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 640)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    private func fieldRow(label: String, info: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            infoTitle(label, info: info)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingRow<Content: View>(label: String, info: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                infoTitle(label, info: info)
            }
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func infoTitle(_ label: String, info: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        Text(info)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
