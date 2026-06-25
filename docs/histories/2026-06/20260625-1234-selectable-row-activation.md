## [2026-06-25 12:34] | Task: Selectable row activation

### 🤖 Execution Context
* **Agent ID**: `codex`
* **Base Model**: `GPT-5`
* **Runtime**: `local macOS CLI`

### 📥 User Query
> Improve Jarvis GUI-control row activation generically after a safe settings
> row was policy-allowed but did not activate through OpenComputerUse.

### 🛠 Changes Overview
**Scope:** OpenComputerUse macOS click handling

**Key Actions:**
- **Broadened row selection**: List, table, outline, and browser row clicks now
  resolve selectable container attributes by AX role.
- **Added fallback selection**: If container selection is unavailable, the row
  item itself can be selected through `AXSelected`.
- **Covered mapping behavior**: Added tests for the role-to-selection-attribute
  mapping used by the generic click path.

### 🧠 Design Intent (Why)
Some macOS sidebars expose rows as selectable without making
`AXSelectedChildren` settable on the immediate list container. The click path
should try the semantic selection mechanisms exposed by the AX role before
falling back to less reliable pointer behavior. This keeps the fix generic and
avoids app-name or label special cases.

### 📁 Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
