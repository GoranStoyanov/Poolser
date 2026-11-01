import Foundation

/// What one protocol loader (v3 or v4) produced for one chain.
struct LoaderOutput {
    var positions: [Position] = []
    var feesUSD: Double = 0
    var error: String?
    /// v4 only: the Transfer-log scan has not reached the chain head yet.
    var bootstrapInProgress = false
    /// v4 only: first unscanned block, where the accelerated follow-up continues.
    var bootstrapNextFromBlock: Int?
}

/// Combined v3 + v4 result for one chain, kept per chain between refreshes.
struct ChainLoadResult {
    let chain: SupportedChain
    var positions: [Position]
    let feesUSD: Double
    let error: String?
    let bootstrapInProgress: Bool
    let bootstrapNextFromBlock: Int?
    var failedV3 = false
    var failedV4 = false

    /// When every chain has the same failure, one message is enough for the wallet.
    static func sharedFailure(_ results: [ChainLoadResult]) -> String? {
        guard results.count > 1, results.allSatisfy({ $0.error != nil }) else { return nil }
        let messages = results.compactMap { result -> String? in
            guard let error = result.error else { return nil }
            let prefix = "\(result.chain.displayName): "
            return error.hasPrefix(prefix) ? String(error.dropFirst(prefix.count)) : error
        }
        guard let first = messages.first, messages.allSatisfy({ $0 == first }) else { return nil }
        return "\(first) (all \(results.count) networks)"
    }

    static func failed(_ chain: SupportedChain, error: String) -> ChainLoadResult {
        ChainLoadResult(
            chain: chain,
            positions: [],
            feesUSD: 0,
            error: error,
            bootstrapInProgress: false,
            bootstrapNextFromBlock: nil,
            failedV3: true,
            failedV4: true
        )
    }
}

/// An error whose message is shown to the user as-is.
struct LoaderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
