// swift-tools-version: 6.2
import PackageDescription

let nrsc5BuildTreePath = "\(Context.packageDirectory)/Vendor/nrsc5/build/src"
let nrsc5LinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L", "Vendor/nrsc5/build/src"]),
    .linkedLibrary("nrsc5"),
]
let nrsc5BuildTreeRpath: [LinkerSetting] = [
    .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", nrsc5BuildTreePath]),
]

let package = Package(
    name: "TunedTwo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "TunedTwo", targets: ["TunedTwo"]),
        .executable(name: "tunedtwo-cli", targets: ["TunedTwoCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.7.4"),
        .package(url: "https://github.com/groue/grdb.swift", from: "7.11.1"),
    ],
    targets: [
        .systemLibrary(name: "CNrsc5"),

        .target(
            name: "TunedTwoCore",
            dependencies: [
                "CNrsc5",
                .product(name: "Collections", package: "swift-collections"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings
        ),

        .executableTarget(
            name: "TunedTwo",
            dependencies: ["TunedTwoCore"],
            path: "Sources/TunedTwo",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath + [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),

        .executableTarget(
            name: "TunedTwoCLI",
            dependencies: [
                "TunedTwoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TunedTwoCLI",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath + [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        ),

        .testTarget(
            name: "TunedTwoTests",
            dependencies: ["TunedTwoCore"],
            path: "Tests/TunedTwoTests",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath
        ),
    ]
)
