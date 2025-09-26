// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XCBusiness",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "XCBusiness",
            targets: ["XCBusiness"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/min554357332/XCNetwork.git", .upToNextMajor(from: "0.0.1"))
    ],
    targets: [
        .target(
            name: "XCBusiness",
            dependencies: [
                "XCNetwork"
            ]
        ),
        .testTarget(
            name: "XCBusinessTests",
            dependencies: [
                "XCBusiness",
                "XCNetwork",
            ]
        ),
    ]
)
