import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject  private var service: UniswapService
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            settingsSection("Ethereum Configuration") {
                VStack(spacing: 0) {
                    fieldRow(
                        label: "Wallet Address",
                        info: "Address to inspect for v3/v4 NFT liquidity positions.",
                        placeholder: "0x…",
                        text: $settings.walletAddress
                    )
                    Divider().opacity(0.35).padding(.leading, 14)
                    fieldRow(
                        label: "RPC URL",
                        info: "HTTPS JSON-RPC endpoint used for all on-chain reads.",
                        placeholder: "https://mainnet.infura.io/v3/…",
                        text: $settings.rpcURL
                    )
                }
                .glassCard(cornerRadius: 12)
            }

            settingsSection("Performance & RPC") {
                VStack(spacing: 0) {
                    settingRow(
                        label: "Refresh Interval",
                        info: "Automatic refresh cadence in minutes."
                    ) {
                        Stepper(value: $settings.refreshIntervalMinutes, in: 1...120) {
                            Text("\(settings.refreshIntervalMinutes) min")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .frame(width: 140, alignment: .trailing)
                    }
                    Divider().opacity(0.35).padding(.leading, 14)
                    settingRow(
                        label: "RPC Credit Budget",
                        info: "Max client-side request pacing budget (credits per second)."
                    ) {
                        Stepper(value: $settings.rpcCreditsPerSecondBudget, in: 50...5_000, step: 25) {
                            Text("\(settings.rpcCreditsPerSecondBudget) cps")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .frame(width: 140, alignment: .trailing)
                    }
                    Divider().opacity(0.35).padding(.leading, 14)
                    settingRow(
                        label: "v4 Log Chunk Size",
                        info: "Blocks per eth_getLogs request during v4 ownership discovery."
                    ) {
                        Stepper(value: $settings.v4LogChunkSize, in: 1_000...50_000, step: 1_000) {
                            Text("\(settings.v4LogChunkSize)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .frame(width: 140, alignment: .trailing)
                    }
                    Divider().opacity(0.35).padding(.leading, 14)
                    settingRow(
                        label: "v4 Log Concurrency",
                        info: "Parallel eth_getLogs requests during v4 scanning."
                    ) {
                        Stepper(value: $settings.v4LogMaxConcurrentRequests, in: 1...8) {
                            Text("\(settings.v4LogMaxConcurrentRequests)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .frame(width: 140, alignment: .trailing)
                    }
                    Divider().opacity(0.35).padding(.leading, 14)
                    settingRow(
                        label: "Bootstrap Chunks / Refresh",
                        info: "Max v4 history chunks scanned in one refresh cycle."
                    ) {
                        Stepper(value: $settings.v4BootstrapMaxChunksPerRefresh, in: 5...200, step: 5) {
                            Text("\(settings.v4BootstrapMaxChunksPerRefresh)")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        .frame(width: 140, alignment: .trailing)
                    }
                    Divider().opacity(0.35).padding(.leading, 14)
                    HStack {
                        Spacer()
                        Button("Reset Performance Defaults") {
                            settings.resetPerformanceDefaults()
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
                            get: { settings.launchAtLogin },
                            set: { newValue in Task { await settings.setLaunchAtLogin(newValue) } }
                        ))
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

            HStack {
                Spacer()
                Button("Save & Refresh") {
                    service.refresh()
                    onDismiss?()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
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
