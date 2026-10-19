// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bakdo",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "Vendor/build-apple/whisper.xcframework"
        ),
        .binaryTarget(
            name: "llama",
            path: "Vendor/build-apple/llama.xcframework"
        ),
        .executableTarget(
            name: "Bakdo",
            dependencies: ["whisper", "llama"],
            path: "Sources/Bakdo",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
    ]
)
