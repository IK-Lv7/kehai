// swift-tools-version: 5.9
import PackageDescription

// 画面に依存しない、判定ルールだけのパッケージ。Linux 上でもテストできる。
let package = Package(
    name: "KehaiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KehaiCore", targets: ["KehaiCore"]),
    ],
    targets: [
        .target(name: "KehaiCore"),
        .testTarget(name: "KehaiCoreTests", dependencies: ["KehaiCore"]),
    ]
)
