import Foundation
import Testing
@testable import Poolser

@Suite("ABI decoding")
struct ABIDecodingTests {
    @Test func hexRoundTrip() throws {
        let data = try #require(Data(hexString: "0x00ff10Ab"))
        #expect(data == Data([0x00, 0xff, 0x10, 0xab]))
        #expect(data.hexString == "00ff10ab")
        #expect(Data(hexString: "abc") == nil)
        #expect(Data(hexString: "zz") == nil)
    }

    @Test func readUInt64UsesLastEightBytesOfWord() {
        var data = Data(count: 64)
        data[23] = 0xff  // outside the low 8 bytes, ignored
        data[30] = 0x01
        data[31] = 0xf4
        #expect(data.readUInt64(wordAt: 0) == 500)
        #expect(data.readUInt64(wordAt: 33) == 0)  // word runs past the end
    }

    @Test func readAddressSkipsPadding() throws {
        let data = try #require(Data(hexString:
            "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"))
        #expect(data.readAddress(wordAt: 0) == "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        #expect(Data(count: 16).readAddress(wordAt: 0) == "0x" + String(repeating: "0", count: 40))
    }

    @Test("readInt24 sign-extends the low 3 bytes", arguments: [
        ("fffff6", -10),
        ("0d89e8", 887_272),
        ("f27618", -887_272),
        ("000000", 0),
        ("7fffff", 8_388_607),
        ("800000", -8_388_608),
    ])
    func readInt24(low: String, expected: Int) throws {
        // Real int24 words are sign-extended across all 32 bytes.
        let pad = expected < 0 ? String(repeating: "ff", count: 29) : String(repeating: "00", count: 29)
        let data = try #require(Data(hexString: pad + low))
        #expect(data.readInt24(wordAt: 0) == expected)
    }

    @Test func readInt24ShortDataReturnsZero() {
        #expect(Data(repeating: 0xff, count: 31).readInt24(wordAt: 0) == 0)
    }

    @Test func readInt24AtReadsUnalignedBytes() {
        let data = Data([0xaa, 0xff, 0xff, 0xf6, 0x0d, 0x89, 0xe8])
        #expect(data.readInt24At(byteOffset: 1) == -10)
        #expect(data.readInt24At(byteOffset: 4) == 887_272)
        #expect(data.readInt24At(byteOffset: 5) == 0)  // runs past the end
    }

    @Test func readWordAndZeroWord() {
        var data = Data(count: 64)
        data[63] = 1
        #expect(data.isZeroWord(at: 0))
        #expect(!data.isZeroWord(at: 32))
        #expect(data.readWord(at: 32).last == 1)
        #expect(data.readWord(at: 40) == Data(count: 32))
    }

    @Test func readAmountScalesByDecimals() {
        var data = Data(count: 32)
        // 1_500_000 = 0x16e360
        data[29] = 0x16; data[30] = 0xe3; data[31] = 0x60
        #expect(data.readAmount(wordAt: 0, decimals: 6) == 1.5)
    }

    @Test func readABIStringStandardLayout() throws {
        let data = try #require(Data(hexString:
            "0000000000000000000000000000000000000000000000000000000000000020"
          + "0000000000000000000000000000000000000000000000000000000000000004"
          + "5553444300000000000000000000000000000000000000000000000000000000"))
        #expect(data.readABIString() == "USDC")
    }

    @Test func readABIStringFallsBackToBytes32() throws {
        // MKR / SAI-era tokens return `bytes32` from symbol(), not `string`.
        let data = try #require(Data(hexString:
            "4d4b520000000000000000000000000000000000000000000000000000000000"))
        #expect(data.readABIString() == "MKR")
    }

    @Test func readABIStringEmptyOrGarbage() {
        #expect(Data().readABIString() == "")
        #expect(Data(count: 32).readABIString() == "")
    }
}

@Suite("ABI encoding")
struct ABIEncodingTests {
    @Test("encodeInt24 round-trips through readInt24", arguments: [-887_272, -887_220, -10, -1, 0, 1, 10, 887_220, 887_272])
    func int24RoundTrip(value: Int) {
        let word = ABI.encodeInt24(value)
        #expect(word.count == 32)
        #expect(word.readInt24(wordAt: 0) == value)
        #expect(word.prefix(29).allSatisfy { $0 == (value < 0 ? 0xff : 0x00) })
    }

    @Test func encodeAddressPadsAndAcceptsMissingPrefix() {
        let expected = "000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        #expect(ABI.encodeAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48").hexString == expected)
        #expect(ABI.encodeAddress("a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48").hexString == expected)
        #expect(ABI.encodeAddress("0x0") == Data(count: 32))
    }

    @Test func encodeUInt256IsBigEndian() {
        let word = ABI.encodeUInt256(0x0102_0304_0506_0708)
        #expect(word.count == 32)
        #expect(word.prefix(24).allSatisfy { $0 == 0 })
        #expect(word.suffix(8) == Data([1, 2, 3, 4, 5, 6, 7, 8]))
        #expect(word.readUInt64(wordAt: 0) == 0x0102_0304_0506_0708)
    }

    @Test func encodeMaxUInt128() {
        let word = ABI.encodeMaxUInt128()
        #expect(word.prefix(16) == Data(count: 16))
        #expect(word.suffix(16) == Data(repeating: 0xff, count: 16))
    }

    @Test func v3SelectorsMatchSignatures() {
        func sel(_ signature: String) -> Data { keccak256(Data(signature.utf8)).prefix(4) }
        let owner = "0x0000000000000000000000000000000000000001"
        #expect(ABI.callBalanceOf(owner: owner).prefix(4) == sel("balanceOf(address)"))
        #expect(ABI.callOwnerOf(tokenId: 1).prefix(4) == sel("ownerOf(uint256)"))
        #expect(ABI.callTokenOfOwnerByIndex(owner: owner, index: 0).prefix(4) == sel("tokenOfOwnerByIndex(address,uint256)"))
        #expect(ABI.callPositions(tokenId: 1).prefix(4) == sel("positions(uint256)"))
        #expect(ABI.callCollectStatic(tokenId: 1, recipient: owner).prefix(4) == sel("collect((uint256,address,uint128,uint128))"))
        #expect(ABI.callGetPool(token0: owner, token1: owner, fee: 500).prefix(4) == sel("getPool(address,address,uint24)"))
        #expect(ABI.callSlot0() == sel("slot0()"))
        #expect(ABI.callSymbol() == sel("symbol()"))
        #expect(ABI.callDecimals() == sel("decimals()"))
    }

    @Test func v4CalldataLayout() throws {
        let poolId = Data(repeating: 0xab, count: 32)
        let pm = "0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e"

        #expect(ABI.v4CallGetPoolAndPositionInfo(tokenId: 7).hexString
                == "7ba03aad" + ABI.encodeUInt256(7).hexString)
        #expect(ABI.v4CallGetPositionLiquidity(tokenId: 7).prefix(4).hexString == "1efeed33")
        #expect(ABI.v4CallGetSlot0(poolId: poolId) == Data(hexString: "c815641c")! + poolId)
        #expect(ABI.v4CallGetFeeGrowthGlobals(poolId: poolId) == Data(hexString: "9ec538c8")! + poolId)
        #expect(ABI.v4CallGetTickInfo(poolId: poolId, tick: -10)
                == Data(hexString: "7c40f1fe")! + poolId + ABI.encodeInt24(-10))

        let call = ABI.v4CallGetPosition(poolId: poolId, owner: pm, tickLower: -887_270, tickUpper: 887_270, salt: 42)
        #expect(call.count == 4 + 5 * 32)
        #expect(call.prefix(4).hexString == "dacf1d2f")
        let args = call.dropFirst(4)
        let words = Data(args)
        #expect(words.readWord(at: 0) == poolId)
        #expect(words.readAddress(wordAt: 32) == pm.lowercased())
        #expect(words.readInt24(wordAt: 64) == -887_270)
        #expect(words.readInt24(wordAt: 96) == 887_270)
        #expect(words.readUInt64(wordAt: 128) == 42)
    }
}
