import Testing
import DataRaft

@Suite struct BitPackVersionTests {
    @Test(arguments: [
        (0, 0, 0, 0, "0.0.0"),
        (0, 0, 1, 1, "0.0.1"),
        (0, 1, 0, 256, "0.1.0"),
        (1, 0, 0, 1048576, "1.0.0"),
        (15, 15, 15, 15732495, "15.15.15"),
        (123, 456, 78, 129091662, "123.456.78"),
        (255, 255, 255, 267452415, "255.255.255"),
        (4095, 4095, 255, 4294967295, "4095.4095.255")
    ])
    func versionComponents(
        _ major: UInt32,
        _ minor: UInt32,
        _ patch: UInt32,
        _ rawValue: UInt32,
        _ description: String
    ) throws {
        let version = try BitPackVersion(
            major: major,
            minor: minor,
            patch: patch
        )
        
        #expect(version.major == major)
        #expect(version.minor == minor)
        #expect(version.patch == patch)
        #expect(version.rawValue == rawValue)
        #expect(version.description == description)
    }
    
    @Test func majorOverflow() {
        do {
            _ = try BitPackVersion(major: 4096, minor: 0)
            Issue.record("Expected BitPackVersion.Error.majorOverflow, but succeeded")
        } catch BitPackVersion.Error.majorOverflow(let value) {
            let error = BitPackVersion.Error.majorOverflow(value)
            let description = "Major version overflow: \(value). Allowed range: 0...4095."
            #expect(value == 4096)
            #expect(error.localizedDescription == description)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test func minorOverflow() {
        do {
            _ = try BitPackVersion(major: 0, minor: 4096)
            Issue.record("Expected BitPackVersion.Error.minorOverflow, but succeeded")
        } catch BitPackVersion.Error.minorOverflow(let value) {
            let error = BitPackVersion.Error.minorOverflow(value)
            let description = "Minor version overflow: \(value). Allowed range: 0...4095."
            #expect(value == 4096)
            #expect(error.localizedDescription == description)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test func patchOverflow() {
        do {
            _ = try BitPackVersion(major: 0, minor: 0, patch: 256)
            Issue.record("Expected BitPackVersion.Error.patchOverflow, but succeeded")
        } catch BitPackVersion.Error.patchOverflow(let value) {
            let error = BitPackVersion.Error.patchOverflow(value)
            let description = "Patch version overflow: \(value). Allowed range: 0...255."
            #expect(value == 256)
            #expect(error.localizedDescription == description)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test(arguments: try [
        (
            BitPackVersion(major: 0, minor: 0, patch: 0),
            BitPackVersion(major: 0, minor: 0, patch: 1)
        ),
        (
            BitPackVersion(major: 0, minor: 1, patch: 0),
            BitPackVersion(major: 1, minor: 0, patch: 0)
        ),
        (
            BitPackVersion(major: 1, minor: 1, patch: 1),
            BitPackVersion(major: 1, minor: 1, patch: 2)
        ),
        (
            BitPackVersion(major: 5, minor: 0, patch: 255),
            BitPackVersion(major: 5, minor: 1, patch: 0)
        ),
        (
            BitPackVersion(major: 10, minor: 100, patch: 100),
            BitPackVersion(major: 11, minor: 0, patch: 0)
        ),
        (
            BitPackVersion(major: 4094, minor: 4095, patch: 255),
            BitPackVersion(major: 4095, minor: 0, patch: 0)
        )
    ])
    func compare(
        _ versionOne: BitPackVersion,
        _ versionTwo: BitPackVersion
    ) throws {
        #expect(versionOne < versionTwo)
    }
    
    @available(iOS 16.0, *)
    @available(macOS 13.0, *)
    @Test(arguments: [
        ("0.0.0", 0, 0, 0, 0, "0.0.0"),
        ("0.0.1", 0, 0, 1, 1, "0.0.1"),
        ("0.1.0", 0, 1, 0, 256, "0.1.0"),
        ("1.0.0", 1, 0, 0, 1048576, "1.0.0"),
        ("1.2.3", 1, 2, 3, 1049091, "1.2.3"),
        ("123.456.78", 123, 456, 78, 129091662, "123.456.78"),
        ("4095.4095.255", 4095, 4095, 255, 4294967295, "4095.4095.255"),
        ("10.20", 10, 20, 0, 10490880, "10.20.0"),
        ("42.0.13", 42, 0, 13, 44040205, "42.0.13")
    ])
    func fromString(
        _ string: String,
        _ major: UInt32,
        _ minor: UInt32,
        _ patch: UInt32,
        _ rawValue: UInt32,
        _ description: String
    ) throws {
        let version = try BitPackVersion(version: string)
        
        #expect(version.major == major)
        #expect(version.minor == minor)
        #expect(version.patch == patch)
        #expect(version.rawValue == rawValue)
        #expect(version.description == description)
    }
    
    @available(iOS 16.0, *)
    @available(macOS 13.0, *)
    @Test(arguments: [
        "",
        "1",
        "1.",
        ".1",
        "1.2.3.4",
        "1.2.",
        "1..2",
        "a.b.c",
        "1.2.c",
        "01.2.3",
        "1.02.3",
        "1.2.03",
        " 1.2.3",
        "1.2.3 ",
        " 1.2 ",
        "1,2,3",
    ])
    func fromInvalidStrings(_ input: String) {
        do {
            _ = try BitPackVersion(version: input)
            Issue.record("Expected failure for: \(input)")
        } catch BitPackVersion.ParseError.invalidFormat(let str) {
            let error = BitPackVersion.ParseError.invalidFormat(str)
            let description = "Invalid version format: \(str). Expected something like '1.2' or '1.2.3'."
            #expect(str == input)
            #expect(error.localizedDescription == description)
        } catch {
            Issue.record("Unexpected error for: \(input) — \(error)")
        }
    }
    
    @available(iOS 16.0, *)
    @available(macOS 13.0, *)
    @Test func stringLiteralInit() {
        let version: BitPackVersion = "1.2.3"
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)
    }
}
