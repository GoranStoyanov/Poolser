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
    /// The App Group shared with the widgets, named under `PoolserAppGroup` in Info.plist; nil in
    /// the SwiftPM build, which has no Info.plist.
    public static let appGroup: String? = {
        let group = Bundle.main.object(forInfoDictionaryKey: "PoolserAppGroup") as? String
        return group?.isEmpty == false ? group : nil
    }()

    /// Where settings and caches persist. Widgets read only the snapshot file in the App Group
    /// container, so settings stay in `.standard`, where existing installs already keep them.
    public static let store: UserDefaults = .standard
}
