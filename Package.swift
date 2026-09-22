// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "pbxedit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PBXSyntax", targets: ["PBXSyntax"]),
    ],
    targets: [
        .target(name: "PBXSyntax"),
        .testTarget(
            name: "PBXSyntaxTests",
            dependencies: ["PBXSyntax"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
