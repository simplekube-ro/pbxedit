// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pbxedit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PBXSyntax", targets: ["PBXSyntax"]),
        .library(name: "PBXModel", targets: ["PBXModel"]),
        .library(name: "PBXOps", targets: ["PBXOps"]),
        .executable(name: "pbxedit", targets: ["pbxedit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "PBXSyntax"),
        .target(name: "PBXModel", dependencies: ["PBXSyntax"]),
        .target(
            name: "PBXOps",
            dependencies: [
                "PBXModel", "PBXSyntax",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "pbxedit",
            dependencies: [
                "PBXOps", "PBXModel", "PBXSyntax",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "PBXSyntaxTests",
            dependencies: ["PBXSyntax"]
        ),
        .testTarget(
            name: "PBXModelTests",
            dependencies: ["PBXModel", "PBXSyntax"]
        ),
        .testTarget(
            name: "PBXOpsTests",
            dependencies: ["PBXOps", "PBXModel", "PBXSyntax"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["pbxedit", "PBXModel", "PBXSyntax"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
