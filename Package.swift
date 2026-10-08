// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clack",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Clack", targets: ["Clack"])],
    targets: [
        .target(name: "ClackAudio", publicHeadersPath: "include"),
        .executableTarget(name: "Clack", dependencies: ["ClackAudio"],
                          swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
