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
}
