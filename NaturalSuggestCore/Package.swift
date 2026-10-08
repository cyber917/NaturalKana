// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NaturalSuggestCore", platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NaturalKanaStorage", targets: ["NaturalKanaStorage"]), .library(name: "NaturalSuggestCore", targets: ["NaturalSuggestCore"]),
               .library(name: "NaturalSuggestUI", targets: ["NaturalSuggestUI"]),
               .executable(name: "NaturalKanaHelper", targets: ["NaturalKanaHelper"]),
               .executable(name: "NaturalKanaPreview", targets: ["NaturalKanaPreview"]),
               .executable(name: "natural-suggest", targets: ["NaturalSuggestCLI"])],
    targets: [.target(name: "NaturalKanaStorage"), .target(name: "NaturalSuggestCore", dependencies: ["NaturalKanaStorage"], resources: [.copy("Resources")]),
              .target(name: "NaturalSuggestUI", dependencies: ["NaturalSuggestCore", "NaturalKanaStorage"]),
              .executableTarget(name: "NaturalKanaPreview", dependencies: ["NaturalSuggestUI"]),
              .executableTarget(name: "NaturalSuggestCLI", dependencies: ["NaturalSuggestCore", "NaturalKanaStorage"]),
              // Mac menu-bar helper; tools/build_macos_helper.sh wraps it in a signed app with Info.plist and entitlements.
              .executableTarget(name: "NaturalKanaHelper", dependencies: ["NaturalSuggestUI", "NaturalSuggestCore"],
                                exclude: ["Info.plist", "NaturalKanaHelper.entitlements"]),
              .testTarget(name: "NaturalSuggestCoreTests", dependencies: ["NaturalSuggestCore", "NaturalKanaStorage", "NaturalSuggestUI"])])
