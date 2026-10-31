import Foundation

/// A saved wallet address with an optional name of the user's choosing.
public struct SavedWallet: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let address: String
    public var name: String?

    public init(address: String, name: String? = nil) {
        self.address = address
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmed.isEmpty ? nil : trimmed
    }

    public var id: String { address.lowercased() }

    /// The name, or the shortened address for a wallet without one.
    public var displayName: String { name ?? WalletAddress.short(address) }

    public func matches(_ address: String) -> Bool {
        self.address.caseInsensitiveCompare(address.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// Normalized addresses, the first of each address kept, invalid ones dropped.
    static func unique(_ wallets: [SavedWallet]) -> [SavedWallet] {
        var seen = Set<String>()
        return wallets.compactMap { wallet in
            guard let address = WalletAddress.normalize(wallet.address),
                  seen.insert(address.lowercased()).inserted else { return nil }
            return SavedWallet(address: address, name: wallet.name)
        }
    }

    // MARK: - Persistence

    static let defaultsKey = "savedWallets"
    /// Addresses only, written by the first multi-wallet build.
    static let legacyDefaultsKey = "walletAddresses"

    static func load(from defaults: UserDefaults) -> [SavedWallet] {
        if let data = defaults.data(forKey: defaultsKey),
           let wallets = try? JSONDecoder().decode([SavedWallet].self, from: data) {
            return wallets
        }
        return (defaults.stringArray(forKey: legacyDefaultsKey) ?? []).map { SavedWallet(address: $0) }
    }

    static func save(_ wallets: [SavedWallet], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(wallets) else { return }
        // The address list stays behind so an older build still finds its wallets.
        defaults.set(data, forKey: defaultsKey)
    }
}

/// What the app keeps per wallet besides the wallet list.
enum WalletCaches {
    static func remove(wallet: String, from defaults: UserDefaults) {
        defaults.removeObject(forKey: HiddenPositionStore.key(for: wallet))
        FeeHistoryService.clearCache(wallet: wallet, in: defaults)
        V4OwnershipTracker.clearCaches(wallet: wallet, in: defaults)
    }
}

/// The wallet list as edited in Settings, saved with `AppSettings.setWallets`. Shared by the
/// macOS and iOS forms so both read and behave the same.
public struct WalletListDraft: Equatable {
    public static let addressPlaceholder = "Wallet address (0x…)"
    public static let namePlaceholder = "Name (optional)"
    public static let addTitle = "Add Wallet"

    public var wallets: [SavedWallet]
    /// Address of the active wallet.
    public var active: String
    public var newAddress = ""
    public var newName = ""

    public init(wallets: [SavedWallet], active: String) {
        self.wallets = wallets
        self.active = active
    }

    @MainActor
    public init(_ settings: AppSettings) {
        self.init(wallets: settings.wallets, active: settings.walletAddress)
    }

    private var trimmedAddress: String { newAddress.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nil while the field is empty or holds a new, valid address.
    public var newAddressError: String? {
        guard !trimmedAddress.isEmpty else { return nil }
        guard let address = WalletAddress.normalize(trimmedAddress) else {
            return WalletAddress.validationError(for: trimmedAddress)
        }
        return wallets.contains { $0.matches(address) } ? "This wallet is already saved." : nil
    }

    public var canAdd: Bool { !trimmedAddress.isEmpty && newAddressError == nil }

    public func isActive(_ wallet: SavedWallet) -> Bool { wallet.matches(active) }

    public mutating func add() {
        guard canAdd, let address = WalletAddress.normalize(trimmedAddress) else { return }
        wallets.append(SavedWallet(address: address, name: newName))
        if WalletAddress.normalize(active) == nil { active = address }
        newAddress = ""
        newName = ""
    }

    public mutating func remove(_ wallet: SavedWallet) {
        wallets.removeAll { $0.id == wallet.id }
        if wallet.matches(active) { active = wallets.first?.address ?? "" }
    }

    public mutating func rename(_ wallet: SavedWallet, to name: String) {
        guard let index = wallets.firstIndex(where: { $0.id == wallet.id }) else { return }
        wallets[index].name = name.isEmpty ? nil : name
    }

    /// Moves `wallet` to where `target` is.
    public mutating func move(_ wallet: SavedWallet, to target: SavedWallet) {
        guard wallet.id != target.id,
              let from = wallets.firstIndex(where: { $0.id == wallet.id }),
              let to = wallets.firstIndex(where: { $0.id == target.id }) else { return }
        wallets.insert(wallets.remove(at: from), at: to)
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { wallets[$0] }
        var rest = wallets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(insertAt, 0), rest.count))
        wallets = rest
    }

    /// Adds an address typed but not yet added, so Save does not drop it.
    public mutating func addPending() {
        if canAdd { add() }
    }
}

/// What the menu bar title totals.
public enum MenuBarSource: Hashable, Sendable {
    /// Every saved wallet together.
    case allWallets
    /// Whatever page the popover shows.
    case shownPage
    /// One wallet, by `SavedWallet.id`.
    case wallet(String)

    static let allWalletsValue = "all"
    static let shownPageValue = "page"

    init(rawValue: String?) {
        switch rawValue {
        case nil, Self.allWalletsValue?: self = .allWallets
        case Self.shownPageValue?: self = .shownPage
        case let id?: self = .wallet(id.lowercased())
        }
    }

    var rawValue: String {
        switch self {
        case .allWallets: return Self.allWalletsValue
        case .shownPage: return Self.shownPageValue
        case .wallet(let id): return id
        }
    }
}

/// A page of the portfolio: every wallet together, or one of them.
public enum WalletPage: Hashable, Identifiable, Sendable {
    case allWallets
    case wallet(SavedWallet)

    public var id: String {
        switch self {
        case .allWallets: return PortfolioSnapshotStore.allWalletsID
        case .wallet(let wallet): return wallet.id
        }
    }

    public var title: String {
        switch self {
        case .allWallets: return "All Wallets"
        case .wallet(let wallet): return wallet.displayName
        }
    }

    /// Whether the title is a name rather than an address.
    public var hasName: Bool {
        switch self {
        case .allWallets: return true
        case .wallet(let wallet): return wallet.name != nil
        }
    }
}

extension AppSettings {
    /// The pages in swipe order, All Wallets first once there are two wallets.
    public var walletPages: [WalletPage] {
        wallets.count > 1 ? [.allWallets] + wallets.map(WalletPage.wallet) : wallets.map(WalletPage.wallet)
    }

    public var shownPage: WalletPage? {
        isShowingAllWallets ? .allWallets : activeWallet.map(WalletPage.wallet)
    }

    public func show(_ page: WalletPage) {
        switch page {
        case .allWallets:
            showsAllWallets = true
        case .wallet(let wallet):
            showsAllWallets = false
            walletAddress = wallet.address
        }
    }
}
