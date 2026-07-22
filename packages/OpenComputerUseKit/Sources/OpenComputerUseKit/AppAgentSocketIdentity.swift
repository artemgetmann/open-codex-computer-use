import Foundation

/// Builds the local socket name used by one signed app identity.
///
/// Release and development builds have separate macOS privacy grants and must
/// therefore never share an app-agent. Keeping the bundle identifier in the
/// socket name derived from the identifier makes that permission boundary
/// explicit at the transport layer.
public func openComputerUseAppAgentSocketFileName(bundleIdentifier: String) -> String {
    var identityHash: UInt64 = 14_695_981_039_346_656_037

    // FNV-1a gives every bundle identity a deterministic, filesystem-safe key
    // without leaking an unbounded identifier into macOS's 104-byte sockaddr.
    for byte in bundleIdentifier.utf8 {
        identityHash ^= UInt64(byte)
        identityHash &*= 1_099_511_628_211
    }

    return String(format: "ocu-agent-%016llx.sock", identityHash)
}
