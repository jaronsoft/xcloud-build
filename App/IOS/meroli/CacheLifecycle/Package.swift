// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeroliCacheLifecycle",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MeroliCacheLifecycle", targets: ["MeroliCacheLifecycle"])
    ],
    targets: [
        .target(name: "MeroliCacheLifecycle"),
        .testTarget(name: "MeroliCacheLifecycleTests", dependencies: ["MeroliCacheLifecycle"])
    ]
)
