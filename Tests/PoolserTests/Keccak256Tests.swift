import Foundation
import Testing
@testable import PoolserKit

@Suite("Keccak256")
struct Keccak256Tests {
    @Test("Matches known Ethereum vectors", arguments: [
        ("", "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
        ("abc", "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
        ("Transfer(address,address,uint256)", "ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"),
        ("DecreaseLiquidity(uint256,uint128,uint256,uint256)", "26f6a048ee9138f2c0ce266f322cb99228e8d619ae2bff30c67f8dcf9d2377b4"),
    ])
    func knownVectors(input: String, expected: String) {
        #expect(keccak256(Data(input.utf8)).hexString == expected)
    }

    /// Inputs around the 136-byte rate exercise the padding paths: a single block with room for
    /// the 0x01/0x80 bytes, a full block that forces an extra padding block, and multiple blocks.
    /// Input bytes are 0, 1, 2, … (mod 256); expected digests come from an independent implementation.
    @Test("Handles rate-boundary lengths", arguments: [
        (135, "cbdfd9dee5faad3818d6b06f95a219fd290b0e1706f6a82e5a595b9ce9faca62"),
        (136, "7ce759f1ab7f9ce437719970c26b0a66ff11fe3e38e17df89cf5d29c7d7f807e"),
        (137, "ac73d4fae68b8453f764007c1a20ce95994187861f0c3227a3a8e99a73a3b1db"),
        (272, "fdf2ec49e749960d3c8521a0219af8d03e30e2b3bf19bd16150ee0eaf133d66e"),
    ])
    func rateBoundary(length: Int, expected: String) {
        let input = Data((0..<length).map { UInt8($0 % 256) })
        #expect(keccak256(input).hexString == expected)
    }

    @Test func selectorPrefix() {
        #expect(keccak256(Data("balanceOf(address)".utf8)).prefix(4).hexString == "70a08231")
    }
}
