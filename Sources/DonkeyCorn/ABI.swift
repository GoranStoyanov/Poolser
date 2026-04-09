import Foundation

// MARK: - Data helpers

extension Data {
    init?(hexString: String) {
        let clean = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard clean.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self.init(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Last 8 bytes of the 32-byte word at `offset`, interpreted as big-endian UInt64.
    func readUInt64(wordAt offset: Int) -> UInt64 {
        guard offset + 32 <= count else { return 0 }
        var v: UInt64 = 0
        for i in (offset + 24)..<(offset + 32) { v = (v << 8) | UInt64(self[i]) }
        return v
    }

    /// All 32 bytes of the word at `offset` interpreted as a big-endian unsigned integer,
    /// then divided by 10^decimals.  Suitable for token amounts (accepts precision loss).
    func readAmount(wordAt offset: Int, decimals: Int) -> Double {
        guard offset + 32 <= count else { return 0 }
        var v = 0.0
        for i in offset..<(offset + 32) { v = v * 256.0 + Double(self[i]) }
        return v / pow(10.0, Double(decimals))
    }

    /// 20-byte Ethereum address from a 32-byte word (12 zero bytes of padding then address).
    func readAddress(wordAt offset: Int) -> String {
        guard offset + 32 <= count else { return "0x" + String(repeating: "0", count: 40) }
        return "0x" + subdata(in: (offset + 12)..<(offset + 32)).hexString
    }

    /// Sign-extended int24 from the last 3 bytes of a 32-byte word.
    func readInt24(wordAt offset: Int) -> Int {
        guard offset + 32 <= count else { return 0 }
        let raw = (Int(self[offset + 29]) << 16)
                | (Int(self[offset + 30]) << 8)
                |  Int(self[offset + 31])
        return (raw & 0x800000) != 0 ? raw | (-1 << 24) : raw
    }

    /// Sign-extended int24 from an exact byte offset (not word-aligned).
    /// Used for reading v4 PositionInfo ticks which are byte-packed, not word-aligned.
    func readInt24At(byteOffset: Int) -> Int {
        guard byteOffset + 3 <= count else { return 0 }
        let raw = (Int(self[byteOffset])     << 16)
                | (Int(self[byteOffset + 1]) << 8)
                |  Int(self[byteOffset + 2])
        return (raw & 0x800000) != 0 ? raw | (-1 << 24) : raw
    }

    /// True when every byte of the 32-byte word at `offset` is 0x00.
    func isZeroWord(at offset: Int) -> Bool {
        guard offset + 32 <= count else { return true }
        return self[offset..<(offset + 32)].allSatisfy { $0 == 0 }
    }

    /// Raw 32-byte word at `offset` — no numeric conversion.
    /// Use this for uint256 fee-growth accumulators that must stay exact.
    func readWord(at offset: Int) -> Data {
        guard offset + 32 <= count else { return Data(count: 32) }
        return subdata(in: offset..<(offset + 32))
    }

    /// Decode an ABI-encoded `string` return value.
    /// Standard layout: word 0 = offset pointer (0x20), word 1 = length, then UTF-8 bytes.
    /// Falls back to bytes32 null-terminated for non-standard tokens (e.g. old WETH).
    func readABIString() -> String {
        if count >= 64 {
            let ptr = Int(readUInt64(wordAt: 0))
            if ptr + 32 <= count {
                let len = Int(readUInt64(wordAt: ptr))
                if len > 0, ptr + 32 + len <= count {
                    let strData = subdata(in: (ptr + 32)..<(ptr + 32 + len))
                    if let s = String(data: strData, encoding: .utf8), !s.isEmpty { return s }
                }
            }
        }
        // bytes32 fallback
        if count >= 32 {
            let nullTerminated = prefix(32).prefix(while: { $0 != 0 })
            if let s = String(data: nullTerminated, encoding: .utf8), !s.isEmpty { return s }
        }
        return ""
    }
}

// MARK: - ABI encoding

enum ABI {
    /// Encode an Ethereum address into 32 bytes (left-padded with zeros).
    static func encodeAddress(_ addr: String) -> Data {
        var out = Data(count: 32)
        let hex = addr.hasPrefix("0x") ? String(addr.dropFirst(2)) : addr
        let padded = String(repeating: "0", count: max(0, 40 - hex.count)) + hex
        if let bytes = Data(hexString: String(padded.suffix(40))) {
            out.replaceSubrange(12..<32, with: bytes)
        }
        return out
    }

    /// Encode a UInt64 into 32 bytes (big-endian, left-padded with zeros).
    static func encodeUInt256(_ value: UInt64) -> Data {
        var out = Data(count: 32)
        var v = value
        for i in stride(from: 31, through: 24, by: -1) {
            out[i] = UInt8(v & 0xff)
            v >>= 8
        }
        return out
    }

    /// Encode a signed int24 into 32 bytes (sign-extended, big-endian).
    static func encodeInt24(_ value: Int) -> Data {
        var out = Data(count: 32)
        if value < 0 { for i in 0..<29 { out[i] = 0xFF } }
        out[29] = UInt8((value >> 16) & 0xFF)
        out[30] = UInt8((value >>  8) & 0xFF)
        out[31] = UInt8( value        & 0xFF)
        return out
    }

    /// 2^128 − 1 encoded as 32 bytes (used as amount0Max / amount1Max in collect()).
    static func encodeMaxUInt128() -> Data {
        var out = Data(count: 32)
        for i in 16..<32 { out[i] = 0xff }
        return out
    }
}

// MARK: - Function selectors & calldata builders
// Selectors are the first 4 bytes of keccak256(signature) — pre-computed constants.

extension ABI {
    private static let sel_balanceOf           = Data(hexString: "70a08231")! // balanceOf(address)
    private static let sel_ownerOf             = Data(hexString: "6352211e")! // ownerOf(uint256)
    private static let sel_tokenOfOwnerByIndex = Data(hexString: "2f745c59")! // tokenOfOwnerByIndex(address,uint256)
    private static let sel_positions           = Data(hexString: "99fbab88")! // positions(uint256)
    private static let sel_collect             = Data(hexString: "fc6f7865")! // collect((uint256,address,uint128,uint128))
    private static let sel_getPool             = Data(hexString: "1698ee82")! // getPool(address,address,uint24)
    private static let sel_slot0               = Data(hexString: "3850c7bd")! // slot0()
    private static let sel_symbol              = Data(hexString: "95d89b41")! // symbol()
    private static let sel_decimals            = Data(hexString: "313ce567")! // decimals()

    static func callBalanceOf(owner: String) -> Data {
        sel_balanceOf + encodeAddress(owner)
    }

    static func callOwnerOf(tokenId: UInt64) -> Data {
        sel_ownerOf + encodeUInt256(tokenId)
    }

    static func callTokenOfOwnerByIndex(owner: String, index: UInt64) -> Data {
        sel_tokenOfOwnerByIndex + encodeAddress(owner) + encodeUInt256(index)
    }

    static func callPositions(tokenId: UInt64) -> Data {
        sel_positions + encodeUInt256(tokenId)
    }

    /// Simulates collect() via eth_call to read current owed fees without submitting a tx.
    static func callCollectStatic(tokenId: UInt64, recipient: String) -> Data {
        sel_collect
            + encodeUInt256(tokenId)
            + encodeAddress(recipient)
            + encodeMaxUInt128()
            + encodeMaxUInt128()
    }

    static func callGetPool(token0: String, token1: String, fee: Int) -> Data {
        sel_getPool + encodeAddress(token0) + encodeAddress(token1) + encodeUInt256(UInt64(fee))
    }

    static func callSlot0()    -> Data { sel_slot0 }
    static func callSymbol()   -> Data { sel_symbol }
    static func callDecimals() -> Data { sel_decimals }
}

// MARK: - Uniswap v4 calldata builders
// Selectors are computed at runtime via keccak256 — self-verifying against the live ABI.

extension ABI {
    // Selectors computed lazily from their canonical Solidity signatures.
    private static let sel_v4GetPoolAndPositionInfo: Data = {
        keccak256(Data("getPoolAndPositionInfo(uint256)".utf8)).prefix(4)
    }()
    private static let sel_v4GetPositionLiquidity: Data = {
        keccak256(Data("getPositionLiquidity(uint256)".utf8)).prefix(4)
    }()
    private static let sel_v4GetSlot0: Data = {
        keccak256(Data("getSlot0(bytes32)".utf8)).prefix(4)
    }()
    private static let sel_v4GetPosition: Data = {
        keccak256(Data("getPositionInfo(bytes32,address,int24,int24,bytes32)".utf8)).prefix(4)
    }()
    private static let sel_v4GetTickInfo: Data = {
        keccak256(Data("getTickInfo(bytes32,int24)".utf8)).prefix(4)
    }()
    private static let sel_v4GetFeeGrowthGlobals: Data = {
        keccak256(Data("getFeeGrowthGlobals(bytes32)".utf8)).prefix(4)
    }()

    /// PositionManager: getPoolAndPositionInfo(uint256)
    /// Returns: (PoolKey[currency0,currency1,fee,tickSpacing,hooks], PositionInfo[bytes32])
    static func v4CallGetPoolAndPositionInfo(tokenId: UInt64) -> Data {
        sel_v4GetPoolAndPositionInfo + encodeUInt256(tokenId)
    }

    /// PositionManager: getPositionLiquidity(uint256) → uint128
    static func v4CallGetPositionLiquidity(tokenId: UInt64) -> Data {
        sel_v4GetPositionLiquidity + encodeUInt256(tokenId)
    }

    /// StateView: getSlot0(bytes32 poolId) → (uint160 sqrtPriceX96, int24 tick, ...)
    static func v4CallGetSlot0(poolId: Data) -> Data {
        sel_v4GetSlot0 + poolId
    }

    /// StateView: getPositionInfo(bytes32,address,int24,int24,bytes32)
    /// → (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
    /// owner = PositionManager address; salt = bytes32(tokenId)
    static func v4CallGetPosition(poolId: Data, owner: String, tickLower: Int, tickUpper: Int, salt: UInt64) -> Data {
        sel_v4GetPosition + poolId + encodeAddress(owner) + encodeInt24(tickLower) + encodeInt24(tickUpper) + encodeUInt256(salt)
    }

    /// StateView: getTickInfo(bytes32,int24)
    /// → (uint128 liqGross, int128 liqNet, uint256 fgOutside0, uint256 fgOutside1)
    static func v4CallGetTickInfo(poolId: Data, tick: Int) -> Data {
        sel_v4GetTickInfo + poolId + encodeInt24(tick)
    }

    /// StateView: getFeeGrowthGlobals(bytes32) → (uint256 fg0, uint256 fg1)
    static func v4CallGetFeeGrowthGlobals(poolId: Data) -> Data {
        sel_v4GetFeeGrowthGlobals + poolId
    }

    /// Compute the PoolId = keccak256 of the ABI-memory-encoded PoolKey (5 × 32 bytes = 160 bytes).
    /// Matches Solidity: PoolIdLibrary.toId() which hashes raw PoolKey memory.
    static func computeV4PoolId(
        currency0: String, currency1: String,
        fee: Int, tickSpacing: Int, hooks: String
    ) -> Data {
        var input = Data(count: 160)

        // Each field is right-justified in its 32-byte slot (same as ABI encoding).
        func writeAddress(_ addr: String, at slot: Int) {
            let hex = addr.hasPrefix("0x") ? String(addr.dropFirst(2)) : addr
            if let d = Data(hexString: String(repeating: "0", count: max(0, 40 - hex.count)) + hex) {
                input.replaceSubrange((slot + 12)..<(slot + 32), with: d.suffix(20))
            }
        }

        writeAddress(currency0, at: 0)
        writeAddress(currency1, at: 32)

        // fee: uint24 — last 3 bytes of slot at byte 64
        input[93] = UInt8((fee >> 16) & 0xFF)
        input[94] = UInt8((fee >> 8)  & 0xFF)
        input[95] = UInt8( fee        & 0xFF)

        // tickSpacing: int24 sign-extended to 32 bytes at slot 96
        if tickSpacing < 0 { for i in 96..<125 { input[i] = 0xFF } }
        input[125] = UInt8((tickSpacing >> 16) & 0xFF)
        input[126] = UInt8((tickSpacing >> 8)  & 0xFF)
        input[127] = UInt8( tickSpacing        & 0xFF)

        writeAddress(hooks, at: 128)

        return keccak256(input)
    }
}

