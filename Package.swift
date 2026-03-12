// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YTDMacApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YTDMacApp", targets: ["YTDMacApp"])
    ],
    targets: [
        .executableTarget(
            name: "YTDMacApp",
            path: "Sources/YTDMacApp"
        )
    ]
)
