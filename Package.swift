// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoPrintEditor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PhotoPrintEditor", targets: ["PhotoPrintEditor"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")
    ],
    targets: [
        .executableTarget(
            name: "PhotoPrintEditor",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/PhotoPrintEditor"
        )
    ]
)
