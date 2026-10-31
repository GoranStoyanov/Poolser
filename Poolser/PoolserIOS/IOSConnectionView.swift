import SwiftUI
import PoolserKit

struct IOSConnectionView: View {
    @EnvironmentObject private var service: UniswapService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var walletDraft: WalletListDraft
    @State private var apiKey: String
    @State private var enabledChains: Set<String>

    init() {
        let settings = AppSettings.shared
        _walletDraft = State(initialValue: WalletListDraft(settings))
        _apiKey = State(initialValue: settings.infuraAPIKey)
        _enabledChains = State(initialValue: settings.enabledChainIDs)
    }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        (WalletAddress.normalize(walletDraft.active) != nil || walletDraft.canAdd)
            && walletDraft.newAddressError == nil && !trimmedKey.isEmpty && !enabledChains.isEmpty
    }

    var body: some View {
        Form {
            Section {
                ForEach(walletDraft.wallets) { wallet in
                    walletRow(wallet)
                }
                .onDelete { offsets in
                    offsets.map { walletDraft.wallets[$0] }.forEach { walletDraft.remove($0) }
                }
                .onMove { walletDraft.move(fromOffsets: $0, toOffset: $1) }
                TextField(WalletListDraft.addressPlaceholder, text: $walletDraft.newAddress)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                TextField(WalletListDraft.namePlaceholder, text: $walletDraft.newName)
                    .onSubmit { walletDraft.add() }
                Button(WalletListDraft.addTitle) { walletDraft.add() }
                    .disabled(!walletDraft.canAdd)
                if let error = walletDraft.newAddressError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                HStack {
                    Text("Wallets")
                    Spacer()
                    if walletDraft.wallets.count > 1 {
                        EditButton()
                            .font(.footnote)
                    }
                }
            } footer: {
                Text("Every saved wallet loads on each refresh. Swipe left or right on the portfolio to switch.")
            }

            Section {
                SecureField("Infura API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Infura")
            } footer: {
                Text("Your key stays in this device's Keychain. Positions are read directly from chain RPC.")
            }

            Section("Networks") {
                ForEach(SupportedChain.all) { chain in
                    Toggle(chain.displayName, isOn: Binding(
                        get: { enabledChains.contains(chain.id) },
                        set: { enabled in
                            if enabled { enabledChains.insert(chain.id) }
                            else { enabledChains.remove(chain.id) }
                        }
                    ))
                }
            }

            Section {
                if settings.hiddenPositions.isEmpty {
                    Text("Hide a position from its card menu to remove it from all views and totals.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.hiddenPositions) { position in
                        HStack {
                            Text(position.label)
                            Spacer()
                            Button("Show") { settings.showPosition(id: position.id) }
                        }
                    }
                }
            } header: {
                Text("Hidden Positions")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    walletDraft.addPending()
                    settings.setWallets(walletDraft.wallets, active: walletDraft.active)
                    settings.infuraAPIKey = trimmedKey
                    settings.enabledChainIDs = enabledChains
                    service.refreshForWalletChange()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private func walletRow(_ wallet: SavedWallet) -> some View {
        HStack(spacing: 12) {
            Button {
                walletDraft.active = wallet.address
            } label: {
                Image(systemName: walletDraft.isActive(wallet) ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Show \(wallet.displayName)")
            .accessibilityAddTraits(walletDraft.isActive(wallet) ? .isSelected : [])
            VStack(alignment: .leading, spacing: 2) {
                TextField(WalletListDraft.namePlaceholder, text: Binding(
                    get: { wallet.name ?? "" },
                    set: { walletDraft.rename(wallet, to: $0) }
                ))
                Text(WalletAddress.short(wallet.address))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
