# Contributing

Thanks for helping improve HammerForge.

## Scope
- Small, focused changes are preferred.
- Large changes should start with an issue or discussion before a PR.
- Keep changes aligned with the current MVP and architecture.

## How To Contribute
1. Open an issue describing the problem and proposed fix.
2. Keep PRs small and limited to one topic.
3. Update docs and tests when behavior changes.
4. Run formatting and lint checks before submitting: `gdformat --check addons/hammerforge/` and `gdlint addons/hammerforge/`.

## Code Expectations
- Follow the subsystem architecture (LevelRoot is the public API).
- Prefer undo actions that use stable IDs and state snapshots.
- Avoid adding new dependencies unless necessary.

## Communication
- Be clear about tradeoffs and known limitations.
- Include before/after behavior notes in PR descriptions.
