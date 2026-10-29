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

    static func failed(_ chain: SupportedChain, error: String) -> ChainLoadResult {
        ChainLoadResult(
            chain: chain,
            positions: [],
            feesUSD: 0,
            error: error,
            bootstrapInProgress: false,
            bootstrapNextFromBlock: nil
        )
    }
}

/// An error whose message is shown to the user as-is.
struct LoaderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
