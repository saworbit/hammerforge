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
4. Run formatting, lint, and test checks before submitting (see below).

## Code Expectations
- Follow the subsystem architecture (LevelRoot is the public API).
- Prefer undo actions that use stable IDs and state snapshots.
- Avoid adding new dependencies unless necessary.

## Running Checks Locally

### Format + Lint
```
gdformat --check addons/hammerforge/
gdlint addons/hammerforge/
```

### Unit Tests (GUT)
Tests live in `tests/` and use the [GUT](https://github.com/bitwes/Gut) framework (installed in `addons/gut/`).

Run all tests headless:
```
godot --headless -s res://addons/gut/gut_cmdln.gd --path .
```

If you get "class_names not imported", run `godot --headless --import --path .` first.

### Writing Tests
- Test files go in `tests/` with the `test_` prefix (e.g. `test_my_feature.gd`).
- Extend `GutTest` and use `assert_eq`, `assert_true`, `assert_almost_eq`, etc.
- Use root shim scripts (dynamically created GDScript) to avoid circular dependency with LevelRoot. See existing tests for the pattern.
- Keep tests focused: one behavior per test function.

### CI
All checks (format, lint, unit tests) run automatically on push/PR to `main` via GitHub Actions.

## Communication
- Be clear about tradeoffs and known limitations.
- Include before/after behavior notes in PR descriptions.
