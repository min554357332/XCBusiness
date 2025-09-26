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
        .package(url: "https://github.com/min554357332/XCNetwork.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/min554357332/XCKeychain.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/min554357332/XCCache.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/min554357332/VPNConnectionChecker.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/min554357332/CacheDataPreprocessor.git", .upToNextMajor(from: "0.0.1")),
        .package(url: "https://github.com/min554357332/Cache.git", .upToNextMajor(from: "7.4.0")),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.10.2")),
        .package(url: "https://github.com/min554357332/AES_256_CBC.git", .upToNextMajor(from: "0.0.1"))
    ],
    targets: [
        .target(
            name: "XCBusiness",
            dependencies: [
                "XCNetwork",
                "XCKeychain",
                "XCCache",
                "VPNConnectionChecker",
                "CacheDataPreprocessor",
                "Cache",
                "Alamofire",
                "AES_256_CBC"
            ]
        ),
        .testTarget(
            name: "XCBusinessTests",
            dependencies: [
                "XCBusiness",
                "XCNetwork",
                "XCKeychain",
                "XCCache",
                "VPNConnectionChecker",
                "CacheDataPreprocessor",
                "Cache",
                "Alamofire",
                "AES_256_CBC"
            ]
        ),
    ]
)
