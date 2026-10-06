// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EnjinKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "EnjinKit", targets: ["EnjinKit"])],
    targets: [
        .target(name: "EnjinKit"),
        .testTarget(name: "EnjinKitTests", dependencies: ["EnjinKit"], exclude: ["Golden"]),
    ]
)
