## Summary

<!-- What changed and why. Keep the PR limited to one topic. -->

## Before / After Behavior

<!-- Describe the user-visible behavior change. Note known limitations plainly. -->

- Before:
- After:

## Related Issue

<!-- e.g. "Closes #41". Large changes should start from an issue or discussion. -->

## Checks

- [ ] `python tools/run_local_checks.py` passes
- [ ] `godot --headless -s res://addons/gut/gut_cmdln.gd --path . -gexit` passes, after `godot --headless --import --path .`
- [ ] `python tools/check_script_warnings.py --godot <path to godot>` passes, if a script under `addons/hammerforge/` changed. CI runs it in GUT Shard 1, and `run_local_checks.py` cannot
- [ ] Docs updated together where behavior changed (README, guide/spec, ROADMAP status)
- [ ] One line per change under this week in CHANGELOG's `[Unreleased]` (CONTRIBUTING.md, Changelog Entries)
- [ ] `git diff --check` is clean and relative Markdown links resolve
- [ ] No bridge tokens, `user://` settings, verification logs, editor screenshots, or local client overrides committed
- [ ] No local editor bridge addon committed, and `project.godot` carries no locally enabled plugin
