// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RayNotes",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RayNotesCore", targets: ["RayNotesCore"]),
        .executable(name: "RayNotes", targets: ["RayNotes"])
    ],
    targets: [
        .target(name: "RayNotesCore"),
        .executableTarget(name: "RayNotes", dependencies: ["RayNotesCore"]),
        .testTarget(name: "RayNotesCoreTests", dependencies: ["RayNotesCore"])
    ]
)
