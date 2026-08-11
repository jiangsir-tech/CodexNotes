// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexNotesProbe",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexNotesCore", targets: ["CodexNotesCore"]),
        .executable(name: "CodexNotesProbe", targets: ["CodexNotesProbe"]),
        .executable(name: "codex-notes-probe-check", targets: ["CodexNotesProbeCheck"])
    ],
    targets: [
        .target(
            name: "CodexNotesCore",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CodexNotesProbe",
            dependencies: ["CodexNotesCore"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "CodexNotesProbeCheck",
            dependencies: ["CodexNotesCore"]
        ),
        .testTarget(
            name: "CodexNotesCoreTests",
            dependencies: ["CodexNotesCore"]
        ),
        .testTarget(
            name: "CodexNotesProbeTests",
            dependencies: ["CodexNotesProbe", "CodexNotesCore"]
        )
    ]
)
