// swift-tools-version: 5.9
import Foundation
import PackageDescription

let package = Package(
    name: "Moa",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "Moa", targets: ["Moa"])
    ],
    targets: [
        .executableTarget(
            name: "Moa",
            path: "macos-menu-bar",
            swiftSettings: [.define("MOA_TEST_SUPPORT", .when(configuration: .debug))],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Combine"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(name: "MoaTests", dependencies: ["Moa"], path: "Tests")
    ]
)
