import SwiftUI
import PoolserKit

struct IOSConnectionView: View {
    @EnvironmentObject private var service: UniswapService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var wallets: [String]
    @State private var wallet: String
    @State private var newWallet = ""
    @State private var apiKey: String
    @State private var enabledChains: Set<String>

    init() {
        let settings = AppSettings.shared
        _wallets = State(initialValue: settings.walletAddresses)
        _wallet = State(initialValue: settings.walletAddress)
        _apiKey = State(initialValue: settings.infuraAPIKey)
        _enabledChains = State(initialValue: settings.enabledChainIDs)
    }

    private var newWalletError: String? {
        guard !newWallet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let address = WalletAddress.normalize(newWallet) else {
            return WalletAddress.validationError(for: newWallet)
        }
        return wallets.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame })
            ? "This address is already saved." : nil
    }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        (WalletAddress.normalize(wallet) != nil || WalletAddress.normalize(newWallet) != nil)
            && newWalletError == nil && !trimmedKey.isEmpty && !enabledChains.isEmpty
    }

    var body: some View {
        Form {
            Section {
                ForEach(wallets, id: \.self) { address in
                    HStack {
                        Button {
                            wallet = address
                        } label: {
                            Label(address, systemImage: wallet.caseInsensitiveCompare(address) == .orderedSame
                                  ? "largecircle.fill.circle" : "circle")
                                .font(.system(.footnote, design: .monospaced))
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            wallets.removeAll { $0 == address }
                            if wallet == address { wallet = wallets.first ?? "" }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                TextField("Add wallet address", text: $newWallet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                Button("Add Address") { addWallet() }
                    .disabled(newWallet.isEmpty || newWalletError != nil)
                SecureField("Infura API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Connect your portfolio")
            } footer: {
                Text("Your key stays in this device's Keychain. Positions are read directly from chain RPC.")
            }

            if let error = newWalletError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                    if !newWallet.isEmpty { addWallet() }
                    settings.setWalletAddresses(wallets, active: wallet)
                    settings.infuraAPIKey = trimmedKey
                    settings.enabledChainIDs = enabledChains
                    service.refreshForWalletChange()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private func addWallet() {
        guard newWalletError == nil, let address = WalletAddress.normalize(newWallet) else { return }
        wallets.append(address)
        if wallet.isEmpty { wallet = address }
        newWallet = ""
    }
}
