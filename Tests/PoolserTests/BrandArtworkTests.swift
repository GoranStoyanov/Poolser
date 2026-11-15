import SwiftUI
import Testing
@testable import PoolserKit

@Suite("Brand artwork")
struct BrandArtworkTests {
    @Test func characterDecodesFromSharedResourceBundle() throws {
        let image = try #require(PoolCharacterArtwork.image)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
        #if canImport(AppKit)
        #expect(image.tiffRepresentation != nil)
        #endif
    }

    @Test func entrancePeeksRetreatsAndSettlesWithoutClippingTheTop() {
        let timeline = KeyframeTimeline(initialValue: PoolEyeEntrance()) {
            PoolEyeEntrance.keyframes
        }
        let hidden = timeline.value(time: 0)
        let peek = timeline.value(time: 0.44)
        let retreat = timeline.value(time: 0.73)
        let pop = timeline.value(time: 0.98)
        let settled = timeline.value(time: timeline.duration)

        #expect(hidden.depth > 1)
        #expect(peek.depth > 0 && peek.depth < 0.6)
        #expect(retreat.depth > 1)
        #expect(pop.depth < 0)
        #expect(pop.roll > 0 && peek.roll < 0)
        #expect(abs(settled.depth) < 0.001)
        #expect(abs(settled.roll) < 0.001)
        #expect(abs(settled.stretch - 1) < 0.001)
        #expect(timeline.duration <= 1.6)

        for compact in [true, false] {
            let width: CGFloat = compact ? 34 : 52
            let top: CGFloat = compact ? 5 : 7.5
            for frame in 0...90 {
                let pose = timeline.value(time: Double(frame) * timeline.duration / 90)
                // Include the tilted, stretched eye bounds, not just its vertical offset.
                let angle = abs(pose.roll) * .pi / 180
                let eyeHeight = width * 416 / 700 * pose.stretch
                let upperEdge = top + width * 416 / 700 + width * pose.depth
                    - eyeHeight * cos(angle) - width / 2 * sin(angle)
                #expect(upperEdge >= 0)
            }
        }
    }
}
