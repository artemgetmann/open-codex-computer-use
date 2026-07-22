## [2026-07-22 18:16] | Task: Isolate macOS app-agent sockets

### 🤖 Execution Context
* **Agent ID**: Codex
* **Base Model**: GPT-5
* **Runtime**: Codex desktop

### 📥 User Query
> Fix Computer Use hanging when release and development app variants are both installed, then validate the real packaged runtime.

### 🛠 Changes Overview
**Scope:** macOS app-agent proxy, transport ownership, tests, and documentation

**Key Actions:**
- **[Identity isolation]**: Name each Unix socket from the app bundle identifier so release and Dev permission identities cannot collide.
- **[Ownership safety]**: Reject duplicate binds and unlink a socket on shutdown only when the listener still owns that inode.
- **[Fail-closed handshake]**: Re-check agent identity after launch instead of trusting any process that accepts the socket connection.
- **[Regression coverage]**: Lock release-versus-Dev isolation, deterministic naming, and the Unix path-length budget in unit tests.

### 🧠 Design Intent (Why)
The previous global socket let any newly launched app-agent unlink the active endpoint. Release and Dev helpers could then remain alive on different socket inodes while callers connected unpredictably or hung. Transport ownership now follows the same bundle identity boundary as macOS privacy permissions.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentSocketIdentity.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/releases/feature-release-notes.md`
