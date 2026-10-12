// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CalendarBar", platforms: [.macOS(.v13)],
  products: [.executable(name: "CalendarBar", targets: ["CalendarBar"])],
  targets: [
    .target(name: "CalendarCore"),
    .executableTarget(name: "CalendarBar", dependencies: ["CalendarCore"]),
    .executableTarget(
      name: "CalendarChecks", dependencies: ["CalendarCore"], path: "Tests/CalendarCoreTests"),
  ])
