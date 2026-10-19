// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileShift",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FileShift",
            path: "Sources/FileShift",
            exclude: ["Resources"]
        )
    ]
)
