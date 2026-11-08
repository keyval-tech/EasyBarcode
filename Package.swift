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
    dependencies: [
        .package(url: "https://github.com/TheAcharya/XLKit.git", from: "1.1.8")
    ],
    targets: [
        .target(
            name: "BarcodeKit",
            dependencies: [.product(name: "XLKit", package: "XLKit")],
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
