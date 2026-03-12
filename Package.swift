// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VideoEasyTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VideoEasyTool", targets: ["VideoEasyTool"])
    ],
    targets: [
        .executableTarget(
            name: "VideoEasyTool",
            path: "Sources/VideoEasyTool"
        )
    ]
)
