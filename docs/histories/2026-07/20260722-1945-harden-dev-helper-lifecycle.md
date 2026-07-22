## [2026-07-22 19:45] | Task: Harden Dev helper lifecycle

### 🤖 Execution Context
* **Agent ID**: `Codex native lifecycle worker`
* **Base Model**: `GPT-5`
* **Runtime**: `Codex macOS workspace`

### 📥 User Query
> Prevent normal consumer verification from showing the Open Computer Use Dev permission UI or leaving Dev app-agents running, while preserving an explicit engineering path.

### 🛠 Changes Overview
**Scope:** macOS app-agent, permission onboarding, and repository E2E lifecycle

**Key Actions:**
- **[Explicit Dev onboarding]**: Require `OPEN_COMPUTER_USE_DEV_ONBOARDING=1` before a Dev bundle may present permission onboarding; production behavior stays unchanged.
- **[Owned cleanup]**: Attach a unique owner token only to app-agents launched by a verification invocation, then terminate only that owned agent on normal exit, failure, timeout, or signal.
- **[Regression proof]**: Cover onboarding policy, owner-token mismatch safety, and E2E cleanup across success, failure, timeout, and `TERM`.

### 🧠 Design Intent (Why)
Dev and production bundle IDs must remain separate for macOS privacy isolation, but routine validation should not create a second permission journey or adopt a pre-existing developer agent. Token-scoped cleanup preserves both boundaries without broad process killing.

### 📁 Files Modified
- `apps/OpenComputerUse/Sources/OpenComputerUse/MacOSAppAgentProxy.swift`
- `apps/OpenComputerUse/Sources/OpenComputerUse/OpenComputerUseMain.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/AppAgentSocketIdentity.swift`
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/Permissions.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `scripts/run-permission-onboarding-e2e.sh`
- `scripts/test-permission-onboarding-e2e-cleanup.sh`
