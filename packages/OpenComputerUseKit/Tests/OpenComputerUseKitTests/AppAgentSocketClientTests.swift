import Darwin
import Foundation
import XCTest
@testable import OpenComputerUseKit

final class AppAgentSocketClientTests: XCTestCase {
    func testReachableButUnresponsiveAgentHandshakeTimesOut() throws {
        let (client, silentPeerFD) = try makeSocketPair()
        defer { close(silentPeerFD) }
        let appURL = try makeTemporaryAppBundle()
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

        let startedAt = Date()
        XCTAssertThrowsError(try client.identityStatus(for: appURL, timeout: 0.1)) { error in
            XCTAssertEqual(
                (error as? LocalizedError)?.errorDescription,
                "Timed out waiting for Open Computer Use.app agent response."
            )
        }

        // The assertion leaves generous scheduler headroom while proving the
        // reachable socket no longer inherits the caller's outer 30s timeout.
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testHealthyAgentIsReusedWithoutLeakingHandshakeTimeout() throws {
        let (client, peerFD) = try makeSocketPair()
        let appURL = try makeTemporaryAppBundle()
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

        let identityResponse: [String: Any] = [
            "bundleIdentifier": "com.example.OpenComputerUseTests",
            "bundleURL": appURL.standardizedFileURL.path,
            "executableURL": appURL
                .appendingPathComponent("Contents/MacOS/TestAgent")
                .standardizedFileURL
                .path,
            "processStartTime": Date().addingTimeInterval(1).timeIntervalSince1970,
        ]

        // The fake healthy agent answers the handshake immediately, then takes
        // longer than that short timeout to answer an ordinary request. The
        // second response must still succeed because healthy reuse restores
        // normal blocking request behavior.
        try runFakeAgent(
            peerFD: peerFD,
            responses: [
                (delay: 0, object: identityResponse),
                (delay: 0.2, object: ["ok": true]),
            ]
        )

        XCTAssertEqual(try client.identityStatus(for: appURL, timeout: 0.1), .current)
        let response = try client.request(["kind": "ping"])
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    func testIdentityMismatchRemainsUnverified() throws {
        let (client, peerFD) = try makeSocketPair()
        let appURL = try makeTemporaryAppBundle()
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

        try runFakeAgent(
            peerFD: peerFD,
            responses: [
                (
                    delay: 0,
                    object: [
                        "bundleIdentifier": "com.example.UnrelatedAgent",
                        "bundleURL": appURL.standardizedFileURL.path,
                        "processStartTime": Date().timeIntervalSince1970,
                    ]
                ),
            ]
        )

        XCTAssertEqual(try client.identityStatus(for: appURL, timeout: 0.1), .unverified)
    }

    private func makeSocketPair() throws -> (AppAgentSocketClient, Int32) {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        do {
            return (try AppAgentSocketClient(fileDescriptor: descriptors[0]), descriptors[1])
        } catch {
            close(descriptors[1])
            throw error
        }
    }

    private func makeTemporaryAppBundle() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocu-agent-client-tests-\(UUID().uuidString)", isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Open Computer Use.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let executableDirectoryURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectoryURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.OpenComputerUseTests",
            "CFBundleExecutable": "TestAgent",
            "CFBundlePackageType": "APPL",
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data("#!/bin/sh\n".utf8).write(to: executableDirectoryURL.appendingPathComponent("TestAgent"))
        return appURL
    }

    private func runFakeAgent(
        peerFD: Int32,
        responses: [(delay: TimeInterval, object: [String: Any])]
    ) throws {
        // Serialize Foundation's `[String: Any]` before entering the Sendable
        // thread closure; immutable `Data` is safe to transfer across it.
        let encodedResponses = try responses.map { response in
            FakeAgentResponse(
                delay: response.delay,
                data: try JSONSerialization.data(
                    withJSONObject: response.object,
                    options: [.withoutEscapingSlashes]
                )
            )
        }

        Thread.detachNewThread {
            defer { close(peerFD) }

            for response in encodedResponses {
                guard Self.readLine(fileDescriptor: peerFD) != nil else {
                    return
                }
                if response.delay > 0 {
                    Thread.sleep(forTimeInterval: response.delay)
                }
                guard Self.writeLine(response.data, fileDescriptor: peerFD) else {
                    return
                }
            }
        }
    }

    private static func readLine(fileDescriptor: Int32) -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0

        while true {
            let count = Darwin.read(fileDescriptor, &byte, 1)
            guard count > 0 else {
                return nil
            }
            if byte == 10 {
                return String(data: Data(bytes), encoding: .utf8)
            }
            bytes.append(byte)
        }
    }

    private static func writeLine(_ data: Data, fileDescriptor: Int32) -> Bool {
        var output = data
        output.append(10)

        return output.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }
            return Darwin.write(fileDescriptor, baseAddress, bytes.count) == bytes.count
        }
    }

    private struct FakeAgentResponse: Sendable {
        let delay: TimeInterval
        let data: Data
    }
}
