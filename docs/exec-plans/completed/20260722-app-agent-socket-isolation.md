# macOS app-agent socket isolation

## Goal

Prevent release and development Open Computer Use app-agents from replacing each other's local transport, then prove the packaged release path still controls a real app.

## Scope and constraints

- Keep app-scoped Accessibility and Screen Recording execution unchanged.
- Preserve local-only Unix socket transport with owner-only permissions.
- Fail closed when a connected agent does not match the selected app bundle.
- Avoid coordinate, clipboard, or AppleScript fallbacks during live proof.

## Risks and rollback

- Existing global socket files become unused and are harmless; the first new command creates the identity-scoped socket.
- If identity resolution fails, automation returns an explicit error instead of running under an unknown permission principal.
- Rollback is the single code commit plus its documentation.

## Verification

- Run focused socket-name tests and the full Swift test suite.
- Run repository document checks.
- Package the macOS app and verify release and Dev helpers use separate socket paths.
- Exercise a reversible TextEdit action through the packaged release CLI.

## Progress

- [x] Reproduce multiple agents sharing the global socket.
- [x] Define bundle-scoped transport and listener ownership rules.
- [x] Pass automated tests and document checks.
- [x] Validate packaged release and Dev coexistence.
- [x] Prepare the tested native change for review and downstream Jarvis consumption.
