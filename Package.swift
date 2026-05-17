// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BluetoothTerminal",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "BluetoothTerminal", targets: ["BluetoothTerminal"]),
    ],
    targets: [
        .target(
            name: "BluetoothTerminal",
            path: "bluetooth terminal",
            exclude: [
                "Assets.xcassets",
                "BluetoothTerminalApp.swift",
            ],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .testTarget(
            name: "BluetoothTerminalTests",
            dependencies: ["BluetoothTerminal"],
            path: "BluetoothTerminalTests"
        ),
    ]
)
