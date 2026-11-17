// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpotiText",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "SpotiText", path: "Sources/SpotiText")
    ]
)
