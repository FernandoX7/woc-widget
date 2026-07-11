// swift-tools-version:6.0
import PackageDescription

// Builds ONLY the SwiftUI-free logic library (Sources/WoCKit) and its tests. The app itself is
// built/bundled by build.sh (raw swiftc over the whole Sources tree); SwiftPM never compiles the
// App/Views sources — they are undeclared directories SwiftPM ignores. `swiftLanguageModes: [.v5]`
// matches the language mode build.sh compiles under, so the two builds can't diverge.
let package = Package(
    name: "WoC",
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "WoCKit", path: "Sources/WoCKit"),
        .testTarget(name: "WoCKitTests", dependencies: ["WoCKit"], path: "Tests/WoCKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
