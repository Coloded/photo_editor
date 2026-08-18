// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoPrintEditor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PhotoPrintEditor", targets: ["PhotoPrintEditor"])
    ],
    targets: [
        .executableTarget(
            name: "PhotoPrintEditor",
            path: "Sources/PhotoPrintEditor"
        )
    ]
)
