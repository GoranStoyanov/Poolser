import SwiftUI
import PoolserKit

struct IOSConnectionView: View {
    @EnvironmentObject private var service: UniswapService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var wallet: String
    @State private var apiKey: String
    @State private var enabledChains: Set<String>

    init() {
        let settings = AppSettings.shared
        _wallet = State(initialValue: settings.walletAddress)
        _apiKey = State(initialValue: settings.infuraAPIKey)
        _enabledChains = State(initialValue: settings.enabledChainIDs)
    }

    private var normalizedWallet: String? { WalletAddress.normalize(wallet) }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        normalizedWallet != nil && !trimmedKey.isEmpty && !enabledChains.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Wallet address", text: $wallet)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                SecureField("Infura API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Connect your portfolio")
            } footer: {
                Text("Your key stays in this device's Keychain. Positions are read directly from chain RPC.")
            }

            if let error = WalletAddress.validationError(for: wallet) {
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
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let normalizedWallet else { return }
                    settings.walletAddress = normalizedWallet
                    settings.infuraAPIKey = trimmedKey
                    settings.enabledChainIDs = enabledChains
                    service.refreshForWalletChange()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
