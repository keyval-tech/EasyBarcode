// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyBarcode",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "EasyBarcode", targets: ["EasyBarcode"]),
        .library(name: "BarcodeKit", targets: ["BarcodeKit"])
    ],
    targets: [
        .target(
            name: "BarcodeKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "EasyBarcode",
            dependencies: ["BarcodeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BarcodeKitTests",
            dependencies: ["BarcodeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
