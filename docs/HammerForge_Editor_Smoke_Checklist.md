# HammerForge Editor Smoke Checklist

Last updated: March 27, 2026

This checklist covers the editor-only flows that are hard to validate in headless tests:
- tutorial banner startup before `LevelRoot` exists
- live dock/tab interaction while the tutorial is visible
- shortcut dialog behavior in the real dock
- prefab save + drag/drop + undo/redo
- subtract preview toggle in the viewport

## Prep

Reset HammerForge user prefs to a known state:

```bash
godot --headless -s res://tools/prepare_editor_smoke.gd --path .
```

To verify tutorial resume behavior instead of a fresh start:

```bash
godot --headless -s res://tools/prepare_editor_smoke.gd --path . -- --tutorial-step=3
```

Then open:

- `res://samples/hf_editor_smoke_start.tscn`

Enable the HammerForge plugin if it is not already enabled.

## Checklist

### 1. Fresh Tutorial Startup
- Open `hf_editor_smoke_start.tscn`.
- Confirm there is no `LevelRoot` in the scene tree yet.
- Confirm the HammerForge dock shows the tutorial immediately.
- Confirm the tutorial title, body text, and progress bar are populated.
- Confirm the four dock tabs remain visible and clickable while the tutorial is shown.
- Switch between `Brush`, `Paint`, `Entities`, and `Manage`; confirm the tutorial banner remains visible and the dock does not collapse or blank.

### 2. Late `LevelRoot` Hookup
- In the 3D viewport, create or trigger creation of `LevelRoot` using the normal plugin workflow.
- Confirm the tutorial remains on step 1 rather than resetting or disappearing.
- Confirm step 1 advances only after adding a brush, not merely because `LevelRoot` appeared.

### 3. Guided Step Flow
- Step 1: draw an additive room brush; confirm the tutorial advances.
- Step 2: draw a subtractive brush overlapping the room; confirm the tutorial advances only for subtraction.
- Step 3: switch to `Paint`, enable Paint Mode, and paint floor cells; confirm the tutorial advances.
- Step 4: switch to `Entities` and drag an entity into the viewport; confirm the tutorial advances.
- Step 5: switch to `Manage` and run Bake.
- Confirm `bake_finished(false)` does not complete the tutorial.
- Confirm only a successful bake completes the tutorial.
- Confirm the completion state auto-closes after the short delay.

### 4. Tutorial Resume
- Close Godot.
- Run `prepare_editor_smoke.gd` with `--tutorial-step=3`.
- Reopen `hf_editor_smoke_start.tscn`.
- Confirm the tutorial resumes at the saved step instead of restarting from step 1.

### 5. Shortcut Dialog
- Click the `?` shortcut button in the dock toolbar.
- Confirm the dialog opens at editor size without visual clipping.
- Type a filter such as `paint`; confirm only matching actions remain visible.
- Clear the filter; confirm categories repopulate correctly.
- Close the dialog with both Enter and Escape paths.

### 6. Prefab Save + Drag/Drop
- Select at least one brush or entity.
- In `Manage -> Prefabs`, save a prefab with a unique test name.
- Confirm the prefab list refreshes and the new item appears.
- Drag the prefab from the list into the 3D viewport.
- Confirm the prefab instances at the snapped placement point.
- If the prefab contains only entities, confirm the placement still succeeds.
- Undo the placement; confirm the full prefab placement is reverted.
- Redo the placement; confirm it is restored.

### 7. Subtract Preview
- Open `Manage -> Settings`.
- Toggle `Subtract Preview` on.
- Create an additive brush and a subtractive brush with real overlap.
- Confirm the red wireframe preview appears on the overlap volume.
- Move or resize either brush; confirm the preview updates.
- Toggle `Subtract Preview` off; confirm the wireframe is removed.

### 8. Cleanup / Persistence
- Dismiss the tutorial with and without `Don't show again` checked.
- Restart Godot and confirm the `show_welcome` preference behaves as expected.
- Reopen the dock and confirm no layout corruption remains after closing the tutorial and shortcut dialog.

## Expected Outcome

If all steps pass, the remaining risk on the tutorial/prefab/shortcut/subtract-preview feature set is low and limited mainly to edge cases outside this smoke path.
