import Foundation

/// A read-only contract call.
struct ContractCall: Hashable {
    let target: String
    let data: Data

    static func == (lhs: ContractCall, rhs: ContractCall) -> Bool {
        lhs.target.lowercased() == rhs.target.lowercased() && lhs.data == rhs.data
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(target.lowercased())
        hasher.combine(data)
    }
}

/// Reads batches of contract calls through the chain's Multicall3, or with one eth_call per
/// read where the chain has none. Either way each read gets its own result, so one that
/// reverts degrades only what depends on it.
struct ContractReader {
    let eth: EthereumClient
    let multicall3: String?
    /// Keeps each aggregate3 well inside providers' eth_call gas and response-size caps.
    var maxCallsPerBatch = 100
    /// Past block to read at; nil reads the latest state.
    var block: Int?

    /// One result per call, in call order. Identical calls are sent once.
    /// A sub-call that reverts inside Multicall3 fails with `EthereumClient.Err.reverted`,
    /// like the same eth_call on its own would.
    func read(_ calls: [ContractCall], context: String) async -> [Result<Data, Error>] {
        var unique: [ContractCall] = []
        var indexOf: [ContractCall: Int] = [:]
        let slots = calls.map { call -> Int in
            if let index = indexOf[call] { return index }
            indexOf[call] = unique.count
            unique.append(call)
            return unique.count - 1
        }
        guard !unique.isEmpty else { return [] }

        let results: [Result<Data, Error>]
        if let multicall3 {
            var batched: [Result<Data, Error>] = []
            for start in stride(from: 0, to: unique.count, by: maxCallsPerBatch) {
                let chunk = Array(unique[start..<min(start + maxCallsPerBatch, unique.count)])
                batched += await aggregate(chunk, via: multicall3, context: context)
            }
            results = batched
        } else {
            results = await individually(unique)
        }
        return slots.map { results[$0] }
    }

    /// `read`, then one more pass over the reads that failed for a reason other than a revert.
    /// A refresh that loses a read to a rate limit or a dropped request would otherwise show
    /// positions without their pool state until the next refresh.
    func readRetryingFailures(_ calls: [ContractCall], context: String) async -> [Result<Data, Error>] {
        var results = await read(calls, context: context)
        let failed = results.indices.filter { Self.isRetryable(results[$0]) }
        guard !failed.isEmpty else { return results }
        let again = await read(failed.map { calls[$0] }, context: "\(context) retry")
        for (index, result) in zip(failed, again) { results[index] = result }
        return results
    }

    private static func isRetryable(_ result: Result<Data, Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        if case EthereumClient.Err.reverted = error { return false }
        return true
    }

    private func aggregate(
        _ calls: [ContractCall],
        via multicall3: String,
        context: String
    ) async -> [Result<Data, Error>] {
        // A lone call gains nothing from Multicall3, and sent directly it keeps the node's own
        // error message.
        if calls.count == 1 { return [await single(calls[0])] }
        do {
            let results = try await eth.aggregate3(
                calls.map { Call3(target: $0.target, allowFailure: true, data: $0.data) },
                multicall3: multicall3,
                context: context,
                block: block
            )
            return results.map { result in
                result.success
                    ? .success(result.returnData)
                    : .failure(EthereumClient.Err.reverted(ABI.revertMessage(result.returnData)))
            }
        } catch where Self.isBatchTooLarge(error) {
            // With allowFailure set, sub-call reverts never revert the batch, so this one ran
            // out of gas: split it until the halves fit.
            let middle = calls.count / 2
            let head = await aggregate(Array(calls[..<middle]), via: multicall3, context: context)
            let tail = await aggregate(Array(calls[middle...]), via: multicall3, context: context)
            return head + tail
        } catch {
            // The request itself failed, so every read in it fails with that error, as each
            // would have on its own eth_call.
            return Array(repeating: .failure(error), count: calls.count)
        }
    }

    private func individually(_ calls: [ContractCall]) async -> [Result<Data, Error>] {
        await withTaskGroup(of: (Int, Result<Data, Error>).self) { group in
            for (index, call) in calls.enumerated() {
                group.addTask { (index, await single(call)) }
            }
            var results = [Result<Data, Error>](repeating: .failure(EthereumClient.Err.noResult), count: calls.count)
            for await (index, result) in group { results[index] = result }
            return results
        }
    }

    private func single(_ call: ContractCall) async -> Result<Data, Error> {
        do {
            if let block {
                return .success(try await eth.ethCall(to: call.target, data: call.data, block: block))
            }
            return .success(try await eth.ethCall(to: call.target, data: call.data))
        } catch {
            return .failure(error)
        }
    }

    private static func isBatchTooLarge(_ error: Error) -> Bool {
        switch error {
        case EthereumClient.Err.reverted:
            return true
        case EthereumClient.Err.rpc(let message):
            return message.lowercased().contains("gas")
        default:
            return false
        }
    }
}
