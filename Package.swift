// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pbxedit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PBXSyntax", targets: ["PBXSyntax"]),
        .library(name: "PBXModel", targets: ["PBXModel"]),
    ],
    targets: [
        .target(name: "PBXSyntax"),
        .target(name: "PBXModel", dependencies: ["PBXSyntax"]),
        .testTarget(
            name: "PBXSyntaxTests",
            dependencies: ["PBXSyntax"]
        ),
        .testTarget(
            name: "PBXModelTests",
            dependencies: ["PBXModel", "PBXSyntax"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
