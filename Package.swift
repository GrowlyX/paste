// swift-tools-version:5.10
import Foundation
import PackageDescription

// SwiftUI's @State is a macro; CommandLineTools lacks the macro plugin, Xcode ships it.
// Point XCODE_PATH elsewhere if Xcode isn't at /Applications/Xcode.app.
let xcode = ProcessInfo.processInfo.environment["XCODE_PATH"] ?? "/Applications/Xcode.app"
let plugins = xcode + "/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

let package = Package(
    name: "Paste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Paste",
            path: "Sources/Paste",
            swiftSettings: [
                .unsafeFlags(["-plugin-path", plugins]),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("LinkPresentation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
