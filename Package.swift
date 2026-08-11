// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "netBee",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "netBee",
            path: "Sources/netBee",
            exclude: ["Info.plist"],
            resources: [.copy("Assets/AppIcon.icns")],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Network"),
            ]
        ),
        .testTarget(
            name: "netBeeTests",
            path: "Tests/netBeeTests"
            // Tests are self-contained — no dependency on the executable target.
            // Pure Swift SPM executables cannot be linked as test dependencies.
        )
    ]
)
