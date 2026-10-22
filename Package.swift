// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPAKit",
    platforms: [.iOS(.v17), .macOS("15.0")],
    products: [
        .library(name: "IPAKit", targets: ["IPAKit"]),
        .library(name: "CredentialKit", targets: ["CredentialKit"]),
        .library(name: "SigningKit", targets: ["SigningKit"]),
        .library(name: "InstallKit", targets: ["InstallKit"]),
        .library(name: "SourcesKit", targets: ["SourcesKit"]),
        .executable(name: "signer-poc", targets: ["signer-poc"]),
    ],
    targets: [
        .target(name: "IPAKit"),
        .testTarget(name: "IPAKitTests", dependencies: ["IPAKit"]),
        .target(name: "CredentialKit"),
        .target(name: "SigningKit", dependencies: ["CredentialKit", "IPAKit"]),
        .target(name: "InstallKit"),
        .target(name: "SourcesKit"),
        .testTarget(name: "SourcesKitTests", dependencies: ["SourcesKit"]),
        .testTarget(name: "InstallKitTests", dependencies: ["InstallKit"]),
        .executableTarget(name: "signer-poc", dependencies: ["SigningKit", "CredentialKit", "IPAKit"]),
        .testTarget(name: "SigningKitTests", dependencies: ["SigningKit", "CredentialKit", "IPAKit"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "CredentialKitTests", dependencies: ["CredentialKit"],
                    exclude: ["generate_fixtures.py"], resources: [.copy("Fixtures")]),
    ]
)
