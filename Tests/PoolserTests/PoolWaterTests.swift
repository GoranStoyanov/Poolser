import SwiftUI
import Testing
@testable import PoolserKit

@Suite("Fee pool water")
struct PoolWaterTests {
    @Test(arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func fillMatchesReturn(_ level: Double) {
        #expect(PoolWater.fill(level: level, base: 0) == level)
    }

    @Test func visualLimitsDoNotOverflow() {
        #expect(PoolWater.fill(level: -0.5, base: 0) == 0)
        #expect(PoolWater.fill(level: 1.5, base: 0) == 1)
        #expect(PoolWater.fill(level: .infinity, base: 0) == 1)
        #expect(PoolWater.fill(level: .nan, base: 0) == 0)
        #expect(PoolWater.fill(level: 0.5, base: 0.1) == 0.55)
    }

    @Test func emptyAndFullHaveNoWaveGap() {
        let rect = CGRect(x: 0, y: 0, width: 347.5, height: 320)
        #expect(Wave(level: 0, phase: 1, amplitude: 8, tilt: 9).path(in: rect).isEmpty)
        #expect(Wave(level: 1, phase: 1, amplitude: 8, tilt: 9).path(in: rect).boundingRect == rect)
    }

    @Test(arguments: [0.001, 0.25, 0.5, 0.999])
    func sloshStaysWithinContainer(_ level: Double) {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 320)
        let wave = Wave(level: level, phase: .pi / 2, amplitude: 8, tilt: 9)
        let bounds = wave.path(in: rect).boundingRect
        #expect(bounds.minY >= rect.minY)
        #expect(bounds.maxY <= rect.maxY)
        #expect(bounds.minY <= rect.height * (1 - level) + 8 + 9)
        #expect(bounds.minY >= rect.height * (1 - level) - 8 - 9)
    }
}
