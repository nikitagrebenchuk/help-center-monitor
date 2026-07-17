// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HelpCenterMonitor",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "HelpCenterCore", targets: ["HelpCenterCore"]),
        .library(name: "HelpCenterSlack", targets: ["HelpCenterSlack"]),
        .executable(name: "HelpCenterMonitor", targets: ["HelpCenterMonitor"]),
        .executable(name: "HelpCenterCoreSelfTest", targets: ["HelpCenterCoreSelfTest"]),
    ],
    targets: [
        .target(name: "HelpCenterCore"),
        .target(
            name: "HelpCenterSlack",
            dependencies: ["HelpCenterCore"]
        ),
        .target(name: "HelpCenterUI"),
        .executableTarget(
            name: "HelpCenterMonitor",
            dependencies: ["HelpCenterCore", "HelpCenterSlack", "HelpCenterUI"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "HelpCenterCoreSelfTest",
            dependencies: ["HelpCenterCore", "HelpCenterSlack", "HelpCenterUI"],
            path: "Tests/HelpCenterCoreSelfTest"
        ),
    ],
    swiftLanguageModes: [.v5]
)
