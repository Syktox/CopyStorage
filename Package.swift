// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipboardHistory", targets: ["ClipboardHistory"])
    ],
    targets: [
        .executableTarget(
            name: "ClipboardHistory",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "ClipboardHistoryTests",
            dependencies: ["ClipboardHistory"]
        )
    ],
    swiftLanguageModes: [.v5]
)
