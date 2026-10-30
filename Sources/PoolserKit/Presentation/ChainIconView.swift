import SwiftUI

public struct ChainIconView: View {
    let chain: SupportedChain
    let size: CGFloat
    @ObservedObject private var iconStore = NetworkIconStore.shared

    public init(chain: SupportedChain, size: CGFloat = 16) {
        self.chain = chain
        self.size = size
    }

    public var body: some View {
        Group {
            if let icon = iconStore.icon(for: chain) {
                Image(platformImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.6)
        )
        .onAppear {
            Task { await iconStore.prefetch(for: [chain]) }
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
            Text(String(chain.displayName.prefix(1)).uppercased())
                .font(.system(size: max(8, size * 0.55), weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
