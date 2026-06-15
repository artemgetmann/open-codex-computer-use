# Raise Activates Frontmost

## Request

Patch the OpenComputerUse restore path so a window-level `Raise` can satisfy
OpenClaw workspace restore proof without AppleScript, coordinate targeting, or
external macOS focus hacks.

## Changes

- Strengthened `perform_secondary_action` for `Raise` by activating the target
  app through `NSRunningApplication.activate(.activateAllWindows)` after the AX
  raise succeeds.
- Added a frontmost verification step against `NSWorkspace.frontmostApplication`
  and the target PID so the tool returns an error instead of reporting success
  when macOS keeps a different app frontmost.
- Kept non-`Raise` secondary actions on the existing AX-only path.
- Added a unit test for the frontmost PID matcher.

## Motivation

`AXUIElementPerformAction(..., AXRaise)` can reorder or expose a window without
making the owning app frontmost. OpenClaw's workspace restore benchmark needs
the stronger postcondition: the requested source app must actually become the
frontmost app after restore.

## Files

- `packages/OpenComputerUseKit/Sources/OpenComputerUseKit/ComputerUseService.swift`
- `packages/OpenComputerUseKit/Tests/OpenComputerUseKitTests/OpenComputerUseKitTests.swift`

## Validation

- Passed: `swift test`
