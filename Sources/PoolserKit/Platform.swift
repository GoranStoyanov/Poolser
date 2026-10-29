import SwiftUI
#if canImport(AppKit)
import AppKit

public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit

public typealias PlatformImage = UIImage
#endif

extension Image {
    public init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

public enum Clipboard {
    public static func copy(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = string
        #endif
    }
}

public enum PoolserDefaults {
    /// Where settings and caches persist. An app that shares them with a widget names its App
    /// Group under `PoolserAppGroup` in Info.plist; the Mac app names none and keeps `.standard`.
    public static let store: UserDefaults = {
        if let group = Bundle.main.object(forInfoDictionaryKey: "PoolserAppGroup") as? String,
           let suite = UserDefaults(suiteName: group) {
            return suite
        }
        return .standard
    }()
}
