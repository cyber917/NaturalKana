// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NaturalSuggestCore", platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NaturalSuggestCore", targets: ["NaturalSuggestCore"]),
               .library(name: "NaturalSuggestUI", targets: ["NaturalSuggestUI"]),
               .executable(name: "NaturalKanaPreview", targets: ["NaturalKanaPreview"]),
               .executable(name: "natural-suggest", targets: ["NaturalSuggestCLI"])],
    targets: [.target(name: "NaturalSuggestCore", resources: [.copy("Resources")]),
              .target(name: "NaturalSuggestUI", dependencies: ["NaturalSuggestCore"]),
              .executableTarget(name: "NaturalKanaPreview", dependencies: ["NaturalSuggestUI"]),
              .executableTarget(name: "NaturalSuggestCLI", dependencies: ["NaturalSuggestCore"]),
              .testTarget(name: "NaturalSuggestCoreTests", dependencies: ["NaturalSuggestCore"])])
