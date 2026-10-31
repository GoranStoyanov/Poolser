import SwiftUI
import UniformTypeIdentifiers
import PoolserKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject  private var service: UniswapService
    var onDismiss: (() -> Void)? = nil
    @State private var walletDraft: WalletListDraft
    @State private var draggedWallet: SavedWallet?
    @State private var draftInfuraAPIKey: String
    @State private var draftEnabledChainIDs: Set<String>
    @State private var draftRefreshIntervalMinutes: Int
    @State private var draftRPCCreditsPerSecondBudget: Int
    @State private var draftV4LogChunkSize: Int
    @State private var draftV4LogMaxConcurrentRequests: Int
    @State private var draftV4BootstrapMaxChunksPerRefresh: Int
    @State private var draftLaunchAtLogin: Bool
    @State private var draftFlashOnValueChange: Bool
    @State private var draftTrackClaimedFees: Bool
    @State private var draftNotifyOnRangeChange: Bool
    @State private var isAPIKeyRevealed = false

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        let s = AppSettings.shared
        _walletDraft = State(initialValue: WalletListDraft(s))
        _draftInfuraAPIKey = State(initialValue: s.infuraAPIKey)
        _draftEnabledChainIDs = State(initialValue: s.enabledChainIDs)
        _draftRefreshIntervalMinutes = State(initialValue: s.refreshIntervalMinutes)
        _draftRPCCreditsPerSecondBudget = State(initialValue: s.rpcCreditsPerSecondBudget)
        _draftV4LogChunkSize = State(initialValue: s.v4LogChunkSize)
        _draftV4LogMaxConcurrentRequests = State(initialValue: s.v4LogMaxConcurrentRequests)
        _draftV4BootstrapMaxChunksPerRefresh = State(initialValue: s.v4BootstrapMaxChunksPerRefresh)
        _draftLaunchAtLogin = State(initialValue: s.launchAtLogin)
        _draftFlashOnValueChange = State(initialValue: s.flashOnValueChange)
        _draftTrackClaimedFees = State(initialValue: s.trackClaimedFees)
        _draftNotifyOnRangeChange = State(initialValue: s.notifyOnRangeChange)
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
                            walletsRow
                            Divider().opacity(0.35).padding(.leading, 14)
                            apiKeyRow
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

                    settingsSection("Hidden Positions") {
                        VStack(spacing: 0) {
                            if settings.hiddenPositions.isEmpty {
                                Text("Hide a position from its card menu to remove it from all views and totals.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                            } else {
                                ForEach(settings.hiddenPositions) { position in
                                    HStack(spacing: 8) {
                                        Text(position.label)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Spacer()
                                        Button("Show") { settings.showPosition(id: position.id) }
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    if position.id != settings.hiddenPositions.last?.id {
                                        Divider().opacity(0.35).padding(.leading, 14)
                                    }
                                }
                            }
                        }
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
                                label: "Log Chunk Size",
                                info: "Blocks per eth_getLogs request (v4 ownership and claimed fees). Infura allows at most 10,000."
                            ) {
                                Stepper(value: $draftV4LogChunkSize, in: AppSettings.Defaults.v4LogChunkSizeRange, step: 1_000) {
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
                                    draftRefreshIntervalMinutes = AppSettings.Defaults.refreshIntervalMinutes
                                    draftRPCCreditsPerSecondBudget = AppSettings.Defaults.rpcCreditsPerSecondBudget
                                    draftV4LogChunkSize = AppSettings.Defaults.v4LogChunkSize
                                    draftV4LogMaxConcurrentRequests = AppSettings.Defaults.v4LogMaxConcurrentRequests
                                    draftV4BootstrapMaxChunksPerRefresh = AppSettings.Defaults.v4BootstrapMaxChunksPerRefresh
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
                                    Text("Range Change Notifications")
                                        .font(.system(size: 13))
                                    Text("Send a notification when a position moves in or out of range.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $draftNotifyOnRangeChange)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            Divider().opacity(0.35).padding(.leading, 14)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Track Claimed Fees")
                                        .font(.system(size: 13))
                                    Text("Scans on-chain Collect events to show historical claimed fees per v3 position. Makes additional eth_getLogs requests — can be request-heavy on fast-block chains (Base, Arbitrum).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $draftTrackClaimedFees)
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
                Text(AppVersion.label(info: Bundle.main.infoDictionary))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Save & Refresh") {
                    walletDraft.addPending()
                    settings.setWallets(walletDraft.wallets, active: walletDraft.active)
                    settings.infuraAPIKey = draftInfuraAPIKey
                    settings.enabledChainIDs = draftEnabledChainIDs
                    settings.refreshIntervalMinutes = draftRefreshIntervalMinutes
                    settings.rpcCreditsPerSecondBudget = draftRPCCreditsPerSecondBudget
                    settings.v4LogChunkSize = draftV4LogChunkSize
                    settings.v4LogMaxConcurrentRequests = draftV4LogMaxConcurrentRequests
                    settings.v4BootstrapMaxChunksPerRefresh = draftV4BootstrapMaxChunksPerRefresh
                    settings.flashOnValueChange = draftFlashOnValueChange
                    settings.notifyOnRangeChange = draftNotifyOnRangeChange
                    settings.trackClaimedFees = draftTrackClaimedFees
                    if settings.launchAtLogin != draftLaunchAtLogin {
                        Task { await settings.setLaunchAtLogin(draftLaunchAtLogin) }
                    }
                    service.refreshForWalletChange()
                    onDismiss?()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(walletDraft.newAddressError != nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 640)
    }

    // MARK: - Wallets

    private var walletsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoTitle(
                "Wallets",
                info: "Every saved wallet loads on each refresh. Swipe left or right in the menu, or press ⌘← and ⌘→, to switch. Drag to reorder."
            )
            ForEach(walletDraft.wallets) { wallet in
                walletRow(wallet)
            }
            VStack(spacing: 6) {
                TextField(WalletListDraft.addressPlaceholder, text: $walletDraft.newAddress)
                    .font(.system(size: 11, design: .monospaced))
                HStack {
                    TextField(WalletListDraft.namePlaceholder, text: $walletDraft.newName)
                        .font(.system(size: 11))
                        .onSubmit { walletDraft.add() }
                    Button(WalletListDraft.addTitle) { walletDraft.add() }
                        .disabled(!walletDraft.canAdd)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, walletDraft.wallets.isEmpty ? 0 : 4)
            if let error = walletDraft.newAddressError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func walletRow(_ wallet: SavedWallet) -> some View {
        HStack(spacing: 8) {
            Button {
                walletDraft.active = wallet.address
            } label: {
                Image(systemName: walletDraft.isActive(wallet) ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.plain)
            .help("Show this wallet")
            .accessibilityLabel("Show \(wallet.displayName)")
            .accessibilityAddTraits(walletDraft.isActive(wallet) ? .isSelected : [])
            VStack(alignment: .leading, spacing: 2) {
                TextField(WalletListDraft.namePlaceholder, text: Binding(
                    get: { wallet.name ?? "" },
                    set: { walletDraft.rename(wallet, to: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                Text(wallet.address)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Button {
                walletDraft.remove(wallet)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("Remove wallet")
            .accessibilityLabel("Remove \(wallet.displayName)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onDrag {
            draggedWallet = wallet
            return NSItemProvider(object: wallet.id as NSString)
        }
        .onDrop(of: [.text], delegate: WalletDropDelegate(target: wallet, dragged: $draggedWallet, draft: $walletDraft))
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

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            infoTitle("Infura API Key", info: "Only the API key is needed. RPC URLs are generated per enabled chain. Stored in the Keychain.")
            HStack(spacing: 6) {
                Group {
                    if isAPIKeyRevealed {
                        TextField("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $draftInfuraAPIKey)
                    } else {
                        SecureField("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", text: $draftInfuraAPIKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                Button {
                    isAPIKeyRevealed.toggle()
                } label: {
                    Image(systemName: isAPIKeyRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isAPIKeyRevealed ? "Hide API key" : "Show API key")
                .accessibilityLabel(isAPIKeyRevealed ? "Hide API key" : "Show API key")
            }
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

/// Reorders the wallet list while a row is dragged over another.
private struct WalletDropDelegate: DropDelegate {
    let target: SavedWallet
    @Binding var dragged: SavedWallet?
    @Binding var draft: WalletListDraft

    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        withAnimation(.snappy) { draft.move(dragged, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

enum AppVersion {
    /// "v1.2 (34)" from the bundle's Info.plist. `swift run` starts a bare executable with no
    /// version keys, so that build is labelled as such instead of "v? (?)".
    static func label(info: [String: Any]?) -> String {
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "development build" }
        guard let build = info?["CFBundleVersion"] as? String else { return "v\(version)" }
        return "v\(version) (\(build))"
    }
}
