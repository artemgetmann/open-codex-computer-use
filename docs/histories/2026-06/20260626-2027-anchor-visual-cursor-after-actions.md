## [2026-06-26 20:27] | Task: Anchor visual cursor after actions

### Execution Context
* **Agent ID**: `Codex`
* **Runtime**: `Codex CLI on macOS`

### User Query
> The Open Computer Use / Jarvis GUI-control virtual cursor selects roughly correct UI targets, but the visible cursor can stay stuck, wiggle, or appear away from the target after recent GUI-control changes.

### Changes Overview
**Scope:** `OpenComputerUseKit` visual cursor completion state

**Key Actions:**
- **[Resting anchor]**: Snap the visual dynamics state to the final target when `click` pulse and `set_value` settle finish, before returning to the app-agent caller.
- **[Regression coverage]**: Added a deterministic helper test for the lagged visual dynamics case that can otherwise leave the rendered tip away from the resting target.

### Design Intent
The movement animation should keep its inertial body/fog lag while traveling. Action completion has a stricter contract: once the click or value-set action is done, the visible cursor must rest on the same target the action used. App-agent callers can return before another idle timer frame is painted, so relying on the next timer frame can leave the overlay frozen in a lagged intermediate position even though the underlying AX action succeeded.

### Files Modified
- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/SoftwareCursorOverlay.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/histories/2026-06/20260626-2027-anchor-visual-cursor-after-actions.md`
