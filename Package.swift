// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Hushbar",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "CHushbarDSP"),
        .executableTarget(name: "Hushbar", dependencies: ["CHushbarDSP"]),
        .testTarget(name: "CHushbarDSPTests", dependencies: ["CHushbarDSP"]),
    ]
)
