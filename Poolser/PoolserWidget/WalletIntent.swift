import AppIntents
import PoolserKit

/// A saved wallet the widget can show, from the list the app writes to the App Group.
struct WalletEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wallet"
    static let defaultQuery = WalletQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WalletQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WalletEntity] {
        savedWallets().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WalletEntity] {
        savedWallets()
    }

    private func savedWallets() -> [WalletEntity] {
        PortfolioSnapshotStore.loadWallets().map { WalletEntity(id: $0.id, name: $0.displayName) }
    }
}

struct SelectWalletIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Wallet"
    static let description = IntentDescription("Choose the wallet this widget shows.")

    /// Nil shows every wallet together.
    @Parameter(title: "Wallet", description: "Leave empty to show all wallets together.")
    var wallet: WalletEntity?
}
