# HammerForge custom tools

Drop a `.gd` file in this folder and HammerForge picks it up on the next editor
launch. This is the folder to use: it sits **outside** `addons/hammerforge`, so
the upgrade instructions ("replace the existing `addons/hammerforge` folder with
the new version") cannot delete your tools.

HammerForge also still scans `res://addons/hammerforge/tools/`, but only so an
existing install does not lose anything. Do not put new work there.

## What a tool has to be

A script that `extends HFEditorTool` and returns a `tool_id()` of **100 or
above**. IDs below 100 are the built-ins (0 = Draw, 1 = Select, 2 = Extrude Up,
3 = Extrude Down) and a tool claiming one is refused with a warning.

```gdscript
@tool
extends HFEditorTool


func tool_name() -> String:
	return "My Tool"


func tool_id() -> int:
	return 100
```

`examples/example_ruler_tool.gd` is a complete working tool. Copy it **up into
this folder** and change the parts you need.

The scan is not recursive, so nothing under `examples/` is registered. That is
deliberate: an example tool should not appear in everyone's toolbar.

## What you get

`HFEditorTool` (`addons/hammerforge/hf_editor_tool.gd`) is the full interface,
and every method has a default, so override only what you use:

| Member | What it is for |
|---|---|
| `root` | The `LevelRoot` the tool is operating on. Set for you on activate. |
| `undo_redo` | The `EditorUndoRedoManager`, for tools that change the level. |
| `history_callback` | Optional; call it with an action name to show up in the dock's history panel. |
| `can_activate(root)` / `get_poll_fail_reason(root)` | Refuse to run, and say why. |
| `activate()` / `deactivate()` | Take and release whatever the tool holds. |
| `handle_input(event, camera, mouse_pos)` | Return `EditorPlugin.AFTER_GUI_INPUT_STOP` to consume the event. |
| `handle_keyboard(event)` | Same, for keys. |
| `tool_shortcut_key()` | A `KEY_*` constant, or 0 for none. |
| `recover_lost_pointer_capture()` / `cancel_pointer_capture()` | Settle a gesture when the release is lost or the window loses focus. |
| `get_shortcut_hud_lines()` | Lines for the viewport shortcut HUD. |

## Rules worth knowing

- A tool that changes the level must go through `undo_redo`. Nothing else will
  make the change undoable.
- `activate()` is where you take anything the tool needs, and `deactivate()` has
  to give all of it back. A tool holding a node after deactivation is the usual
  cause of an orphan.
- The registry frees a rejected instance, so a bad `tool_id()` costs a warning
  and nothing else.
- Tools are loaded once, at editor launch. Restart the editor after adding one.
