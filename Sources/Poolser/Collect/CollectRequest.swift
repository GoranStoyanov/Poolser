import Foundation

/// The transaction that collects a position's unclaimed fees to its owner, ready for a wallet
/// to sign. Poolser never signs: the browser page hands this to the user's wallet.
struct CollectRequest: Equatable {
    let chainId: Int
    let chainName: String
    /// The position manager the transaction is sent to.
    let to: String
    let data: Data
    let owner: String
    let pairLabel: String
    let tokenId: String
    let versionLabel: String
    /// "$84.12" when priced, else the token amounts.
    let feesLabel: String
    let explorerTxPrefix: String?

    /// How long a v4 transaction stays valid after the page is opened.
    static let deadlineWindow: TimeInterval = 20 * 60

    /// Something to collect, a known position manager and, for v4, the PoolKey's currencies.
    static func canCollect(_ pos: Position) -> Bool {
        guard pos.error == nil, pos.feesError == nil, pos.fees0 > 0 || pos.fees1 > 0,
              UInt64(pos.tokenId) != nil, let chain = SupportedChain.byID(pos.chainID) else { return false }
        if pos.isV4 {
            return chain.v4PM != nil && pos.currency0 != nil && pos.currency1 != nil
        }
        return chain.v3NFPM != nil
    }

    init?(position pos: Position, owner: String, now: Date = Date()) {
        guard Self.canCollect(pos), Self.isAddress(owner),
              let tokenId = UInt64(pos.tokenId),
              let chain = SupportedChain.byID(pos.chainID) else { return nil }
        if pos.isV4 {
            guard let manager = chain.v4PM, let currency0 = pos.currency0, let currency1 = pos.currency1 else { return nil }
            to = manager
            data = ABI.v4CallCollectFees(
                tokenId: tokenId, currency0: currency0, currency1: currency1, recipient: owner,
                deadline: UInt64(now.addingTimeInterval(Self.deadlineWindow).timeIntervalSince1970)
            )
        } else {
            guard let manager = chain.v3NFPM else { return nil }
            to = manager
            data = ABI.callCollectStatic(tokenId: tokenId, recipient: owner)
        }
        chainId = chain.chainId
        chainName = chain.displayName
        self.owner = owner
        pairLabel = PositionPresentation(pos).pairLabel
        self.tokenId = pos.tokenId
        versionLabel = pos.versionLabel
        feesLabel = pos.feesUSDLabel ?? pos.feesLabel
        explorerTxPrefix = Self.explorerTxPrefix(chainID: chain.id)
    }

    static func isAddress(_ string: String) -> Bool {
        string.count == 42 && string.hasPrefix("0x") && string.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    static func explorerTxPrefix(chainID: String) -> String? {
        switch chainID {
        case "ethereum":  return "https://etherscan.io/tx/"
        case "base":      return "https://basescan.org/tx/"
        case "arbitrum":  return "https://arbiscan.io/tx/"
        case "optimism":  return "https://optimistic.etherscan.io/tx/"
        case "polygon":   return "https://polygonscan.com/tx/"
        case "bsc":       return "https://bscscan.com/tx/"
        case "avalanche": return "https://snowtrace.io/tx/"
        case "unichain":  return "https://uniscan.xyz/tx/"
        case "linea":     return "https://lineascan.build/tx/"
        case "blast":     return "https://blastscan.io/tx/"
        case "celo":      return "https://celoscan.io/tx/"
        case "zksync":    return "https://explorer.zksync.io/tx/"
        default:          return nil
        }
    }
}
