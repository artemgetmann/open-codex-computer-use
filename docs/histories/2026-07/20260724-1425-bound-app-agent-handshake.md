## [2026-07-24 14:25] | Task: Bound app-agent handshake

### 🤖 Execution Context
* **Agent ID**: Codex
* **Base Model**: GPT-5
* **Runtime**: Codex desktop

### 📥 User Query
> Prevent a reachable but unresponsive macOS app-agent socket from blocking Computer Use until the host timeout, while preserving healthy reuse and safe stale replacement.

### 🛠 Changes Overview
**Scope:** macOS app-agent client transport, reuse policy, regression tests, and reliability docs

**Key Actions:**
- **[Bounded handshake]**: Added a 1-second timeout for identity and lifecycle requests so an unresponsive existing agent cannot wedge startup.
- **[Safe replacement]**: Termination now requires a responsive agent whose bundle path and identifier match the expected app; unverified endpoints are unlinked and replaced without killing their process.
- **[Healthy reuse]**: Reset the socket to normal blocking I/O after a successful handshake so ordinary Computer Use operations do not inherit the short probe timeout.
- **[Regression coverage]**: Added socket-pair tests for a reachable silent peer, healthy reuse after the probe, and mismatched identity remaining unverified.

### 🧠 Design Intent (Why)
The outer host timeout cannot recover the app-agent proxy while its synchronous identity request is blocked in `fgetc`. Bounding only identity and lifecycle traffic restores recovery without imposing an unsafe short deadline on screenshots or other normal GUI operations. Identity must be proven before termination because reachability alone does not establish process ownership.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentSocketClient.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/AppAgentSocketClientTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/RELIABILITY.md`
- `docs/releases/feature-release-notes.md`
