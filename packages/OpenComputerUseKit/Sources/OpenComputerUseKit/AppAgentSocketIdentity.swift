import Foundation

public let openComputerUseAppAgentOwnerEnvironmentKey = "OPEN_COMPUTER_USE_APP_AGENT_OWNER_TOKEN"

private func openComputerUseStableIdentityHash(_ value: String) -> UInt64 {
    var identityHash: UInt64 = 14_695_981_039_346_656_037

    // FNV-1a gives identities a deterministic, filesystem-safe key without
    // leaking arbitrary values into filenames or Unix socket paths.
    for byte in value.utf8 {
        identityHash ^= UInt64(byte)
        identityHash &*= 1_099_511_628_211
    }

    return identityHash
}

public func openComputerUseAppAgentOwnerMatches(expected: String?, requested: String?) -> Bool {
    // Empty tokens never confer ownership. This makes cleanup safe when a
    // launcher discovers an agent that predates its own invocation.
    guard let expected, !expected.isEmpty, let requested, !requested.isEmpty else {
        return false
    }

    return expected == requested
}

public enum OwnedAppAgentTerminationAttempt: Equatable {
    case notReady
    case rejected
    case terminated
}

public func retryOwnedAppAgentTermination(
    maxAttempts: Int,
    attempt: () throws -> OwnedAppAgentTerminationAttempt,
    waitBeforeRetry: () -> Void
) rethrows -> Bool {
    guard maxAttempts > 0 else {
        return false
    }

    for index in 0..<maxAttempts {
        switch try attempt() {
        case .terminated:
            return true
        case .rejected:
            // A live agent with another token is explicitly not ours. Retrying
            // would risk turning lifecycle cleanup into process adoption.
            return false
        case .notReady:
            if index + 1 < maxAttempts {
                waitBeforeRetry()
            }
        }
    }

    return false
}

public func openComputerUseAppAgentOwnerReceiptFileName(
    socketFileName: String,
    ownerToken: String
) -> String {
    let tokenHash = openComputerUseStableIdentityHash(ownerToken)
    return "\(socketFileName).owner-\(String(format: "%016llx", tokenHash))"
}

/// Builds the local socket name used by one signed app identity.
///
/// Release and development builds have separate macOS privacy grants and must
/// therefore never share an app-agent. Keeping the bundle identifier in the
/// socket name derived from the identifier makes that permission boundary
/// explicit at the transport layer.
public func openComputerUseAppAgentSocketFileName(bundleIdentifier: String) -> String {
    let identityHash = openComputerUseStableIdentityHash(bundleIdentifier)

    return String(format: "ocu-agent-%016llx.sock", identityHash)
}
