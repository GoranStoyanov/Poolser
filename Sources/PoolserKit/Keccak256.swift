// Keccak-256 as used by Ethereum.
// This is NOT the same as NIST SHA-3 — the padding byte differs (0x01 vs 0x06).
import Foundation

func keccak256(_ data: Data) -> Data {
    // 1600-bit state as 25 × 64-bit lanes, flattened: index = x + 5*y
    var state = [UInt64](repeating: 0, count: 25)

    let rate = 136  // 1088-bit rate for 256-bit output

    // ── Padding ──────────────────────────────────────────────────────────────
    // Append 0x01, zero-fill to next rate boundary, then XOR 0x80 into last byte.
    var msg = [UInt8](data)
    msg.append(0x01)
    while msg.count % rate != 0 { msg.append(0x00) }
    msg[msg.count - 1] ^= 0x80

    // ── Absorb ───────────────────────────────────────────────────────────────
    for blockStart in stride(from: 0, to: msg.count, by: rate) {
        for i in 0..<(rate / 8) {
            var lane: UInt64 = 0
            for b in 0..<8 { lane |= UInt64(msg[blockStart + i * 8 + b]) << (b * 8) }
            state[i] ^= lane
        }
        keccakF1600(&state)
    }

    // ── Squeeze first 256 bits ───────────────────────────────────────────────
    var result = Data(count: 32)
    for i in 0..<4 {
        let lane = state[i]
        for b in 0..<8 { result[i * 8 + b] = UInt8((lane >> (b * 8)) & 0xFF) }
    }
    return result
}

// MARK: - Keccak-f[1600] permutation

private func keccakF1600(_ A: inout [UInt64]) {
    // Round constants (ι step)
    let rc: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]
    // Rotation offsets rot[x + 5*y]
    let rot: [Int] = [
         0,  1, 62, 28, 27,   // y=0
        36, 44,  6, 55, 20,   // y=1
         3, 10, 43, 25, 39,   // y=2
        41, 45, 15, 21,  8,   // y=3
        18,  2, 61, 56, 14    // y=4
    ]

    for round in 0..<24 {
        // θ
        var C = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 { C[x] = A[x] ^ A[x+5] ^ A[x+10] ^ A[x+15] ^ A[x+20] }
        var D = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 { D[x] = C[(x+4)%5] ^ rotl(C[(x+1)%5], 1) }
        for i in 0..<25 { A[i] ^= D[i % 5] }

        // ρ + π  →  B[y][(2x+3y)%5] = rot(A[x][y], r[x][y])
        var B = [UInt64](repeating: 0, count: 25)
        for x in 0..<5 {
            for y in 0..<5 {
                B[y + 5 * ((2*x + 3*y) % 5)] = rotl(A[x + 5*y], rot[x + 5*y])
            }
        }

        // χ
        for x in 0..<5 {
            for y in 0..<5 {
                A[x + 5*y] = B[x + 5*y] ^ ((~B[(x+1)%5 + 5*y]) & B[(x+2)%5 + 5*y])
            }
        }

        // ι
        A[0] ^= rc[round]
    }
}

@inline(__always)
private func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
    n == 0 ? x : (x << n) | (x >> (64 - n))
}
