## Summary

<!-- What changed and why. Keep the PR limited to one topic. -->

## Before / After Behavior

<!-- Describe the user-visible behavior change. Note known limitations plainly. -->

- Before:
- After:

## Related Issue

<!-- e.g. "Closes #41". Large changes should start from an issue or discussion. -->

## Checks

- [ ] `gdformat --check addons/hammerforge/ tests/` passes
- [ ] `gdlint addons/hammerforge/` passes
- [ ] `godot --headless -s res://addons/gut/gut_cmdln.gd --path .` passes
- [ ] Docs updated together where behavior changed (README, guide/spec, ROADMAP status, `[Unreleased]` in CHANGELOG)
- [ ] `git diff --check` is clean and relative Markdown links resolve
- [ ] No MCP tokens, `user://` settings, verification logs, editor screenshots, or local client overrides committed
- [ ] `addons/godot_mcp` left untouched, or the vendor snapshot was updated deliberately
