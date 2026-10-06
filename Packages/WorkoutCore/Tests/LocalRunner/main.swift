// Entry point for the local (no-XCTest) test runner. See Package.swift.
import Foundation
import XCTest

let filter = CommandLine.arguments.dropFirst().first
exit(XCTestShimRunner.run(filter: filter))
