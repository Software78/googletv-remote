// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleTVKit",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "GoogleTVKit", type: .static, targets: ["GoogleTVKit"]),
        .executable(name: "tvctl", targets: ["tvctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.8.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GoogleTVKit",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .executableTarget(name: "tvctl", dependencies: ["GoogleTVKit"]),
        .testTarget(name: "GoogleTVKitTests", dependencies: ["GoogleTVKit"]),
    ]
)
