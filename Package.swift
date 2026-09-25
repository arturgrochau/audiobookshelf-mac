// swift-tools-version:6.0
import PackageDescription

// Built with Command Line Tools only (no Xcode): no asset catalogs, no
// preview macros. Resources are copied into the bundle by build.sh and
// loaded through Bundle.main, never Bundle.module.
let package = Package(
  name: "Audiobookshelf",
  platforms: [.macOS(.v15)],
  targets: [
    // Pure logic: API models, playback timeline, sync policy, sleep
    // timer, filters. Everything here is unit-tested.
    .target(
      name: "ABSCore",
      path: "Sources/ABSCore",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .executableTarget(
      name: "Audiobookshelf",
      dependencies: ["ABSCore"],
      path: "Sources/Audiobookshelf",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "ABSCoreTests",
      dependencies: ["ABSCore"],
      path: "Tests/ABSCoreTests",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
