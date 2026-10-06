// swift-tools-version:5.9
import PackageDescription

// WorkoutCore: platform-agnostic domain logic for Strong Babe Club.
// Zero third-party dependencies.
//
// Test modes
// - CI / full Xcode:   `swift test` runs Tests/WorkoutCoreTests with real XCTest.
// - Command Line Tools only (no XCTest on disk):
//     WORKOUTCORE_LOCAL_TESTS=1 swift run WorkoutCoreTestRunner
//   builds the *same* test sources as an executable against a tiny
//   XCTest-compatible shim (TestSupport/XCTest) that discovers test methods
//   through the Objective-C runtime. See scripts/test-core.sh.
let localTests = Context.environment["WORKOUTCORE_LOCAL_TESTS"] == "1"

var targets: [Target] = [
    .target(
        name: "WorkoutCore",
        path: "Sources/WorkoutCore",
        swiftSettings: localTests ? [.unsafeFlags(["-enable-testing"])] : []
    ),
    .executableTarget(
        name: "wcplan",
        dependencies: ["WorkoutCore"],
        path: "Sources/wcplan"
    ),
]

if localTests {
    targets += [
        .target(name: "XCTest", path: "TestSupport/XCTest"),
        .executableTarget(
            name: "WorkoutCoreTestRunner",
            dependencies: ["WorkoutCore", "XCTest"],
            path: "Tests",
            exclude: ["Fixtures"],
            sources: ["WorkoutCoreTests", "LocalRunner"]
        ),
    ]
} else {
    targets.append(
        .testTarget(
            name: "WorkoutCoreTests",
            dependencies: ["WorkoutCore"],
            path: "Tests/WorkoutCoreTests"
        )
    )
}

let package = Package(
    name: "WorkoutCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutCore", targets: ["WorkoutCore"]),
    ],
    targets: targets
)
