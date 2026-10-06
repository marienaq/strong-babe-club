// A tiny XCTest-compatible shim used ONLY when real XCTest is unavailable
// (Command Line Tools without Xcode). It is compiled into the local
// `WorkoutCoreTestRunner` executable and never into the app or CI test target.
//
// It implements the subset of the XCTest API the WorkoutCore tests use and
// discovers `test*` methods through the Objective-C runtime, exactly like
// XCTest does on Darwin. Keep test files to this subset so they compile under
// both the shim and real XCTest.

@_exported import Foundation // real XCTest re-exports Foundation
import ObjectiveC

// MARK: - Failure bookkeeping

public struct XCTShimFailure: CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: UInt
    public var description: String { "\(file):\(line): error: \(message)" }
}

enum XCTShimState {
    nonisolated(unsafe) static var failures: [XCTShimFailure] = []
}

func shimRecord(_ message: String, _ file: StaticString, _ line: UInt) {
    XCTShimState.failures.append(XCTShimFailure(message: message, file: "\(file)", line: line))
}

private func suffix(_ message: () -> String) -> String {
    let m = message()
    return m.isEmpty ? "" : " - \(m)"
}

// MARK: - XCTestCase

@objcMembers
open class XCTestCase: NSObject {
    public required override init() { super.init() }
    open func setUp() {}
    open func tearDown() {}
    open func setUpWithError() throws {}
    open func tearDownWithError() throws {}
}

public struct XCTSkip: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String = "") { self.message = message }
    public var description: String { message }
}

struct XCTUnwrapError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Assertions (signatures mirror XCTest)

public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    shimRecord("failed\(message.isEmpty ? "" : " - \(message)")", file, line)
}

public func XCTAssert(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(try expression(), message(), file: file, line: line)
}

public func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                          file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try !expression() { shimRecord("XCTAssertTrue failed\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertTrue threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try expression() { shimRecord("XCTAssertFalse failed\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertFalse threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                         _ message: @autoclosure () -> String = "",
                                         file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try expression1(), b = try expression2()
        if a != b { shimRecord("XCTAssertEqual failed: (\"\(a)\") is not equal to (\"\(b)\")\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertEqual threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertEqual<T: FloatingPoint>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                             accuracy: T, _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try expression1(), b = try expression2()
        if abs(a - b) > accuracy {
            shimRecord("XCTAssertEqual failed: (\"\(a)\") is not equal to (\"\(b)\") +/- (\"\(accuracy)\")\(suffix(message))", file, line)
        }
    } catch { shimRecord("XCTAssertEqual threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertNotEqual<T: Equatable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                            _ message: @autoclosure () -> String = "",
                                            file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try expression1(), b = try expression2()
        if a == b { shimRecord("XCTAssertNotEqual failed: (\"\(a)\") is equal to (\"\(b)\")\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertNotEqual threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    do {
        if let v = try expression() { shimRecord("XCTAssertNil failed: \"\(v)\"\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertNil threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertNotNil(_ expression: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
    do {
        if try expression() == nil { shimRecord("XCTAssertNotNil failed\(suffix(message))", file, line) }
    } catch { shimRecord("XCTAssertNotNil threw \(error)\(suffix(message))", file, line) }
}

private func compare<T: Comparable>(_ name: String, _ e1: () throws -> T, _ e2: () throws -> T, _ ok: (T, T) -> Bool,
                                    _ message: () -> String, _ file: StaticString, _ line: UInt) {
    do {
        let a = try e1(), b = try e2()
        if !ok(a, b) { shimRecord("\(name) failed: (\"\(a)\") vs (\"\(b)\")\(suffix(message))", file, line) }
    } catch { shimRecord("\(name) threw \(error)\(suffix(message))", file, line) }
}

public func XCTAssertGreaterThan<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                _ message: @autoclosure () -> String = "",
                                                file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertGreaterThan", expression1, expression2, >, message, file, line)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                       _ message: @autoclosure () -> String = "",
                                                       file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertGreaterThanOrEqual", expression1, expression2, >=, message, file, line)
}

public func XCTAssertLessThan<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                             _ message: @autoclosure () -> String = "",
                                             file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertLessThan", expression1, expression2, <, message, file, line)
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ expression1: @autoclosure () throws -> T, _ expression2: @autoclosure () throws -> T,
                                                    _ message: @autoclosure () -> String = "",
                                                    file: StaticString = #filePath, line: UInt = #line) {
    compare("XCTAssertLessThanOrEqual", expression1, expression2, <=, message, file, line)
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "",
                                    file: StaticString = #filePath, line: UInt = #line,
                                    _ errorHandler: (_ error: Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        shimRecord("XCTAssertThrowsError failed: did not throw an error\(suffix(message))", file, line)
    } catch {
        errorHandler(error)
    }
}

public func XCTAssertNoThrow<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() } catch {
        shimRecord("XCTAssertNoThrow failed: threw error \"\(error)\"\(suffix(message))", file, line)
    }
}

public func XCTUnwrap<T>(_ expression: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                         file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let v = try expression() { return v }
    let text = "XCTUnwrap failed: expected non-nil value of type \"\(T.self)\"\(suffix(message))"
    shimRecord(text, file, line)
    throw XCTUnwrapError(description: text)
}

// MARK: - Runner

public enum XCTestShimRunner {
    private typealias VoidIMP = @convention(c) (AnyObject, Selector) -> Void
    private typealias ThrowingIMP = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> ObjCBool

    /// Discovers and runs every `test*` method on every `XCTestCase` subclass.
    /// - Parameter filter: optional substring matched against "Class.method".
    /// - Returns: process exit code (0 = all passed).
    public static func run(filter: String? = nil) -> Int32 {
        let classes = testCaseClasses()
        var executed = 0, failedTests = 0, skipped = 0
        let start = Date()
        for cls in classes {
            for (name, sel, throwing) in testMethods(of: cls) {
                let fullName = "\(NSStringFromClass(cls)).\(name)"
                if let filter, !fullName.contains(filter) { continue }
                executed += 1
                let before = XCTShimState.failures.count
                var skipReason: String?
                autoreleasepool {
                    let instance = (cls as! XCTestCase.Type).init()
                    do {
                        try instance.setUpWithError()
                        instance.setUp()
                        invoke(instance, sel, throwing: throwing, skip: &skipReason)
                        instance.tearDown()
                        try instance.tearDownWithError()
                    } catch let s as XCTSkip {
                        skipReason = s.message
                    } catch {
                        shimRecord("setUp/tearDown threw \(error)", #filePath, #line)
                    }
                }
                let newFailures = XCTShimState.failures[before...]
                if let skipReason {
                    skipped += 1
                    print("Test Case '\(fullName)' skipped (\(skipReason))")
                } else if newFailures.isEmpty {
                    print("Test Case '\(fullName)' passed")
                } else {
                    failedTests += 1
                    newFailures.forEach { print($0) }
                    print("Test Case '\(fullName)' failed")
                }
            }
        }
        let secs = String(format: "%.3f", Date().timeIntervalSince(start))
        print("\nExecuted \(executed) tests, with \(failedTests) failures (\(skipped) skipped) in \(secs) seconds")
        return (failedTests == 0 && executed > 0) ? 0 : 1
    }

    private static func invoke(_ obj: XCTestCase, _ sel: Selector, throwing: Bool, skip: inout String?) {
        guard let imp = class_getMethodImplementation(type(of: obj), sel) else { return }
        if throwing {
            let fn = unsafeBitCast(imp, to: ThrowingIMP.self)
            let slot = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
            slot.initialize(to: nil)
            defer { slot.deallocate() }
            let ok = fn(obj, sel, UnsafeMutableRawPointer(slot))
            if !ok.boolValue {
                var errText = "unknown error"
                if let raw = slot.pointee {
                    let err = Unmanaged<NSError>.fromOpaque(raw).takeUnretainedValue()
                    if err.domain.hasSuffix("XCTSkip") {
                        skip = err.localizedDescription
                        return
                    }
                    errText = "\(err)"
                }
                // XCTUnwrap already recorded its own failure; record others.
                if !errText.contains("XCTUnwrapError") {
                    shimRecord("test threw error: \(errText)", #filePath, #line)
                }
            }
        } else {
            unsafeBitCast(imp, to: VoidIMP.self)(obj, sel)
        }
    }

    /// Only classes defined in the runner's own executable image are
    /// inspected, so arbitrary system classes are never touched or messaged.
    private static func testCaseClasses() -> [AnyClass] {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().standardizedFileURL.path else { return [] }
        var imageCount: UInt32 = 0
        let images = objc_copyImageNames(&imageCount)
        defer { free(UnsafeMutableRawPointer(mutating: images)) }
        let base = ObjectIdentifier(XCTestCase.self)
        var result: [AnyClass] = []
        for i in 0..<Int(imageCount) {
            let image = images[i]
            let path = URL(fileURLWithPath: String(cString: image)).resolvingSymlinksInPath().standardizedFileURL.path
            guard path == exe else { continue }
            var classCount: UInt32 = 0
            guard let names = objc_copyClassNamesForImage(image, &classCount) else { continue }
            defer { free(UnsafeMutableRawPointer(mutating: names)) }
            for j in 0..<Int(classCount) {
                guard let cls = objc_getClass(names[j]) as? AnyClass,
                      ObjectIdentifier(cls) != base else { continue }
                var sup: AnyClass? = class_getSuperclass(cls)
                while let s = sup {
                    if ObjectIdentifier(s) == base { result.append(cls); break }
                    sup = class_getSuperclass(s)
                }
            }
        }
        return result.sorted { NSStringFromClass($0) < NSStringFromClass($1) }
    }

    private static func testMethods(of cls: AnyClass) -> [(String, Selector, Bool)] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return [] }
        defer { free(methods) }
        var result: [(String, Selector, Bool)] = []
        for i in 0..<Int(count) {
            let sel = method_getName(methods[i])
            let name = NSStringFromSelector(sel)
            guard name.hasPrefix("test") else { continue }
            if !name.contains(":") {
                result.append((name, sel, false))
            } else if name.hasSuffix("AndReturnError:"), name.filter({ $0 == ":" }).count == 1 {
                result.append((String(name.dropLast("AndReturnError:".count)), sel, true))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }
}
