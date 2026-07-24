import Darwin
import Foundation

/// The identity result returned by a responsive app-agent handshake.
///
/// A caller may terminate only `verifiedStale` agents. A timeout or malformed
/// response is not proof of ownership and must remain `unverified`.
package enum AppAgentIdentityStatus {
    case current
    case verifiedStale
    case unverified
}

/// Synchronous request client for the private CLI-to-app Unix socket.
///
/// Requests are serialized because each response belongs to the immediately
/// preceding request on the same line-framed connection. Callers may bound
/// identity and lifecycle requests without imposing that short timeout on
/// normal Computer Use operations.
package final class AppAgentSocketClient: @unchecked Sendable {
    private let file: UnsafeMutablePointer<FILE>
    private let lock = NSLock()

    package init(fileDescriptor: Int32) throws {
        guard let file = fdopen(fileDescriptor, "r+") else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            close(fileDescriptor)
            throw error
        }
        self.file = file
    }

    deinit {
        fclose(file)
    }

    package static func connect(path: String) -> AppAgentSocketClient? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        let copied = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { buffer -> Bool in
                let bytes = Array(path.utf8)
                guard bytes.count < pathCapacity else {
                    return false
                }
                for index in 0..<bytes.count {
                    buffer[index] = CChar(bitPattern: bytes[index])
                }
                buffer[bytes.count] = 0
                return true
            }
        }

        guard copied else {
            close(fd)
            return nil
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }

        return try? AppAgentSocketClient(fileDescriptor: fd)
    }

    package func request(
        _ object: [String: Any],
        timeout: TimeInterval? = nil
    ) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        // A handshake timeout must not leak into the reused healthy client.
        // A zero timeval restores normal blocking I/O for regular tool calls.
        try configureSocketTimeout(timeout)
        clearerr(file)

        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        guard let line = String(data: data, encoding: .utf8) else {
            throw ComputerUseError.message("Failed to encode app-agent request.")
        }

        try writeClientLine(line)

        guard let responseLine = try readClientLine(),
              let response = try JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any]
        else {
            throw ComputerUseError.message("Open Computer Use.app agent closed the connection.")
        }

        if let error = response["error"] as? String {
            throw ComputerUseError.message(error)
        }

        return response
    }

    package func identityStatus(
        for appURL: URL,
        timeout: TimeInterval
    ) throws -> AppAgentIdentityStatus {
        let response = try request(["kind": "agentInfo"], timeout: timeout)
        let expectedBundleURL = appURL.standardizedFileURL

        // Both the bundle path and identifier must match before the caller may
        // treat this process as owned, stale, or eligible for termination.
        guard response["bundleURL"] as? String == expectedBundleURL.path,
              let expectedBundleIdentifier = Bundle(url: expectedBundleURL)?.bundleIdentifier,
              response["bundleIdentifier"] as? String == expectedBundleIdentifier
        else {
            return .unverified
        }

        guard let processStartTime = response["processStartTime"] as? TimeInterval else {
            return .unverified
        }

        guard let executableURL = executableURL(for: expectedBundleURL),
              let modifiedAt = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey])
                  .contentModificationDate
        else {
            return .current
        }

        return processStartTime + 0.5 >= modifiedAt.timeIntervalSince1970 ? .current : .verifiedStale
    }

    package func isCurrentAgent(
        for appURL: URL,
        timeout: TimeInterval = 1
    ) throws -> Bool {
        try identityStatus(for: appURL, timeout: timeout) == .current
    }

    private func configureSocketTimeout(_ timeout: TimeInterval?) throws {
        if let timeout {
            guard timeout.isFinite, timeout > 0 else {
                throw ComputerUseError.message("App-agent request timeout must be greater than zero.")
            }
        }

        let seconds = timeout ?? 0
        let wholeSeconds = floor(seconds)
        var value = timeval(
            tv_sec: Int(wholeSeconds),
            tv_usec: Int32((seconds - wholeSeconds) * 1_000_000)
        )
        let valueSize = socklen_t(MemoryLayout<timeval>.size)
        let fileDescriptor = fileno(file)

        guard setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &value, valueSize) == 0,
              setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &value, valueSize) == 0
        else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    private func readClientLine() throws -> String? {
        var bytes: [UInt8] = []

        while true {
            errno = 0
            let character = fgetc(file)
            if character == EOF {
                let errorNumber = errno
                if ferror(file) != 0 {
                    clearerr(file)
                    if errorNumber == EAGAIN || errorNumber == EWOULDBLOCK {
                        throw ComputerUseError.message("Timed out waiting for Open Computer Use.app agent response.")
                    }
                    throw POSIXError(.init(rawValue: errorNumber) ?? .EIO)
                }
                return bytes.isEmpty ? nil : String(data: Data(bytes), encoding: .utf8)
            }
            if character == 10 {
                return String(data: Data(bytes), encoding: .utf8)
            }
            bytes.append(UInt8(character))
        }
    }

    private func writeClientLine(_ line: String) throws {
        let output = line + "\n"
        errno = 0
        let writeResult = output.withCString { pointer in
            fputs(pointer, file)
        }
        let flushResult = writeResult == EOF ? EOF : fflush(file)
        guard writeResult != EOF, flushResult == 0 else {
            let errorNumber = errno
            clearerr(file)
            if errorNumber == EAGAIN || errorNumber == EWOULDBLOCK {
                throw ComputerUseError.message("Timed out sending request to Open Computer Use.app agent.")
            }
            throw POSIXError(.init(rawValue: errorNumber) ?? .EIO)
        }
    }

    private func executableURL(for appURL: URL) -> URL? {
        guard let bundle = Bundle(url: appURL),
              let executableName = bundle.object(forInfoDictionaryKey: kCFBundleExecutableKey as String) as? String,
              !executableName.isEmpty
        else {
            return nil
        }

        return appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
            .standardizedFileURL
    }
}
