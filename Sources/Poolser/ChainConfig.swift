import Foundation

struct SupportedChain: Identifiable, Hashable {
    let id: String
    let displayName: String
    let chainId: Int
    let infuraHost: String
    let coingeckoPlatformID: String
    let defiLlamaChainKey: String
    let geckoterminalNetworkID: String?
    let v3Factory: String?
    let v3NFPM: String?
    let wrappedNativeToken: String
    let v4PM: String?
    let v4SV: String?
    let v4DeployBlockHex: String?

    /// Chain slug used in Uniswap web app URLs (e.g. ?chain=mainnet)
    var uniswapChainSlug: String {
        switch id {
        case "ethereum": return "mainnet"
        case "bsc":      return "bnb"
        default:         return id
        }
    }

    var supportsV3: Bool {
        v3Factory != nil && v3NFPM != nil
    }

    var supportsV4: Bool {
        v4PM != nil && v4SV != nil && v4DeployBlockHex != nil
    }

    var infuraRPCURLTemplate: String {
        "https://\(infuraHost).infura.io/v3/<YOUR-API-KEY>"
    }

    static let all: [SupportedChain] = [
        SupportedChain(
            id: "ethereum",
            displayName: "Ethereum",
            chainId: 1,
            infuraHost: "mainnet",
            coingeckoPlatformID: "ethereum",
            defiLlamaChainKey: "ethereum",
            geckoterminalNetworkID: "eth",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
            v4PM: "0xbd216513d74c8cf14cf4747e6aaa6420ff64ee9e",
            v4SV: "0x7ffe42c4a5deea5b0fec41c94c136cf115597227",
            v4DeployBlockHex: "0x14af301",
        ),
        SupportedChain(
            id: "base",
            displayName: "Base",
            chainId: 8453,
            infuraHost: "base-mainnet",
            coingeckoPlatformID: "base",
            defiLlamaChainKey: "base",
            geckoterminalNetworkID: "base",
            v3Factory: "0x33128a8fC17869897dcE68Ed026d694621f6FDfD",
            v3NFPM: "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: "0x7c5f5a4bbd8fd63184577525326123b519429bdc",
            v4SV: "0xa3c0c9b65bad0b08107aa264b0f3db444b867a71",
            v4DeployBlockHex: "0x182d351",
        ),
        SupportedChain(
            id: "arbitrum",
            displayName: "Arbitrum",
            chainId: 42161,
            infuraHost: "arbitrum-mainnet",
            coingeckoPlatformID: "arbitrum-one",
            defiLlamaChainKey: "arbitrum",
            geckoterminalNetworkID: "arbitrum",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
            v4PM: "0xd88f38f930b7952f2db2432cb002e7abbf3dd869",
            v4SV: "0x76fd297e2d437cd7f76d50f01afe6160f86e9990",
            v4DeployBlockHex: "0x11c0b8cd",
        ),
        SupportedChain(
            id: "optimism",
            displayName: "Optimism",
            chainId: 10,
            infuraHost: "optimism-mainnet",
            coingeckoPlatformID: "optimistic-ethereum",
            defiLlamaChainKey: "optimism",
            geckoterminalNetworkID: "optimism",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: "0x3c3ea4b57a46241e54610e5f022e5c45859a1017",
            v4SV: "0xc18a3169788f4f75a170290584eca6395c75ecdb",
            v4DeployBlockHex: "0x7ce22bb",
        ),
        SupportedChain(
            id: "polygon",
            displayName: "Polygon",
            chainId: 137,
            infuraHost: "polygon-mainnet",
            coingeckoPlatformID: "polygon-pos",
            defiLlamaChainKey: "polygon",
            geckoterminalNetworkID: "polygon_pos",
            v3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
            v3NFPM: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            wrappedNativeToken: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
            v4PM: "0x1ec2ebf4f37e7363fdfe3551602425af0b3ceef9",
            v4SV: "0x5ea1bd7974c8a611cbab0bdcafcb1d9cc9b3ba5a",
            v4DeployBlockHex: "0x3fe0a2a",
        ),
        SupportedChain(
            id: "blast",
            displayName: "Blast",
            chainId: 81457,
            infuraHost: "blast-mainnet",
            coingeckoPlatformID: "blast",
            defiLlamaChainKey: "blast",
            geckoterminalNetworkID: "blast",
            v3Factory: "0x792edAdE80af5fC680d96a2eD80A44247D2Cf6Fd",
            v3NFPM: "0xB218e4f7cF0533d4696fDfC419A0023D33345F28",
            wrappedNativeToken: "0x4300000000000000000000000000000000000004",
            v4PM: "0x4ad2f4cca2682cbb5b950d660dd458a1d3f1baad",
            v4SV: "0x12a88ae16f46dce4e8b15368008ab3380885df30",
            v4DeployBlockHex: "0xdb6164",
        ),
        SupportedChain(
            id: "palm",
            displayName: "Palm",
            chainId: 11_297_108_109,
            infuraHost: "palm-mainnet",
            coingeckoPlatformID: "palm",
            defiLlamaChainKey: "palm",
            geckoterminalNetworkID: nil,
            v3Factory: nil,
            v3NFPM: nil,
            wrappedNativeToken: "0x0000000000000000000000000000000000000000",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "avalanche",
            displayName: "Avalanche",
            chainId: 43114,
            infuraHost: "avalanche-mainnet",
            coingeckoPlatformID: "avalanche",
            defiLlamaChainKey: "avax",
            geckoterminalNetworkID: "avax",
            v3Factory: "0x740b1c1de25031C31FF4fC9A62f554A55cdC1baD",
            v3NFPM: "0x655C406EBFa14EE2006250925e54ec43AD184f8B",
            wrappedNativeToken: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "celo",
            displayName: "Celo",
            chainId: 42220,
            infuraHost: "celo-mainnet",
            coingeckoPlatformID: "celo",
            defiLlamaChainKey: "celo",
            geckoterminalNetworkID: "celo",
            v3Factory: "0xAfE208a311B21f13EF87E33A90049fC17A7acDEc",
            v3NFPM: "0x3d79EdAaBC0EaB6F08ED885C05Fc0B014290D95A",
            wrappedNativeToken: "0x471EcE3750Da237f93B8E339c536989b8978a438",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "linea",
            displayName: "Linea",
            chainId: 59144,
            infuraHost: "linea-mainnet",
            coingeckoPlatformID: "linea",
            defiLlamaChainKey: "linea",
            geckoterminalNetworkID: "linea",
            v3Factory: nil,
            v3NFPM: nil,
            wrappedNativeToken: "0xE5D7C2a44fA3fAF9A34fD5E24D6fB95f27f7B4F0",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "mantle",
            displayName: "Mantle",
            chainId: 5000,
            infuraHost: "mantle-mainnet",
            coingeckoPlatformID: "mantle",
            defiLlamaChainKey: "mantle",
            geckoterminalNetworkID: "mantle",
            v3Factory: nil,
            v3NFPM: nil,
            wrappedNativeToken: "0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "zksync",
            displayName: "ZKsync",
            chainId: 324,
            infuraHost: "zksync-mainnet",
            coingeckoPlatformID: "zksync",
            defiLlamaChainKey: "era",
            geckoterminalNetworkID: "zksync",
            v3Factory: "0x8FdA5a7a8dCA67BBcDd10F02Fa0649A937215422",
            v3NFPM: "0x0616e5762c1E7Dc3723c50663dF10a162D690a86",
            wrappedNativeToken: "0x5AEA5775959fBC2557Cc8789bC1bf90A239D9a91",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "bsc",
            displayName: "BSC",
            chainId: 56,
            infuraHost: "bsc-mainnet",
            coingeckoPlatformID: "binance-smart-chain",
            defiLlamaChainKey: "bsc",
            geckoterminalNetworkID: "bsc",
            v3Factory: "0xdB1d10011AD0Ff90774D0C6Bb92e5C5c8b4461F7",
            v3NFPM: "0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613",
            wrappedNativeToken: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "megaeth",
            displayName: "MegaETH",
            chainId: 4326,
            infuraHost: "megaeth-mainnet",
            coingeckoPlatformID: "megaeth",
            defiLlamaChainKey: "megaeth",
            geckoterminalNetworkID: nil,
            v3Factory: "0x3a5f0cd7d62452b7f899b2a5758bfa57be0de478",
            v3NFPM: "0xcdc86e98184e96436f733a8bf31bd4f0214e6d7d",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "monad",
            displayName: "Monad",
            chainId: 143,
            infuraHost: "monad-mainnet",
            coingeckoPlatformID: "monad",
            defiLlamaChainKey: "monad",
            geckoterminalNetworkID: nil,
            v3Factory: "0x204faca1764b154221e35c0d20abb3c525710498",
            v3NFPM: "0x7197e214c0b767cfb76fb734ab638e2c192f4e53",
            wrappedNativeToken: "0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A",
            v4PM: nil,
            v4SV: nil,
            v4DeployBlockHex: nil,
        ),
        SupportedChain(
            id: "unichain",
            displayName: "Unichain",
            chainId: 130,
            infuraHost: "unichain-mainnet",
            coingeckoPlatformID: "unichain",
            defiLlamaChainKey: "unichain",
            geckoterminalNetworkID: "unichain",
            v3Factory: "0x1f98400000000000000000000000000000000003",
            v3NFPM: "0x943e6e07a7e8e791dafc44083e54041d743c46e9",
            wrappedNativeToken: "0x4200000000000000000000000000000000000006",
            v4PM: "0x4529a01c7a0410167c5740c487a8de60232617bf",
            v4SV: "0x86e8631a016f9068c3f085faf484ee3f5fdee8f2",
            v4DeployBlockHex: "0x680f5f",
        )
    ]

    static func byID(_ id: String) -> SupportedChain? {
        all.first(where: { $0.id == id })
    }
}
