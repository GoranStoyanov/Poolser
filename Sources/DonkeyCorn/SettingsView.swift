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
                        placeholder: "0x…",
                        text: $settings.walletAddress
                    )
                    Divider().opacity(0.35).padding(.leading, 14)
                    fieldRow(
                        label: "RPC URL",
                        placeholder: "https://mainnet.infura.io/v3/…",
                        text: $settings.rpcURL
                    )
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

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
