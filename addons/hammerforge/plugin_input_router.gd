@tool
class_name HFPluginInputRouter
extends RefCounted
## Viewport keymap dispatch extracted from plugin.gd.
## Surfaces still call plugin._handle_keyboard_input(); this module owns the order.

const HFPluginShortcutsType = preload("plugin_shortcuts.gd")
const LevelRootType = preload("level_root.gd")
const HFKeymapType = preload("hf_keymap.gd")
const HFCommandRegistryType = preload("hf_command_registry.gd")
const HFPluginEditActionsType = preload("plugin_edit_actions.gd")
const HFPluginViewCommandsType = preload("plugin_view_commands.gd")
const HFPluginTransformToolsType = preload("plugin_transform_tools.gd")
const HFPluginMaterialCommandsType = preload("plugin_material_commands.gd")
const HFPluginSelectionCommandsType = preload("plugin_selection_commands.gd")
const HFMaterialBrowserType = preload("ui/hf_material_browser.gd")
const HFPluginSnapFeedbackType = preload("plugin_snap_feedback.gd")
const HFPluginTextureKeysType = preload("plugin_texture_keys.gd")
const STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## Same sentinel as plugin.HF_SHORTCUT_APPLY
const SHORTCUT_APPLY := -3
# plugin.SelectionScope.NATIVE_ONLY
const SCOPE_NATIVE_ONLY := 1
## How much of a grid step an Alt nudge moves (#1431).
const FINE_NUDGE := 0.1


## A key HammerForge handles is consumed, so Godot never sees it (#927). Where
## Godot's 3D editor binds the same chord, it gets the key back while only Godot
## nodes are selected and HammerForge has nothing in progress: E is Rotate for a
## selected light, not Extrude. Paint mode, vertex mode and an active external
## tool keep their keys, because the mapper chose to be in them.
static func yields_to_godot(
	plugin: Object, event: InputEventKey, root: Node, paint_mode: bool
) -> bool:
	if not HFKeymapType.godot_3d_uses(event):
		return false
	if paint_mode or plugin._vertex_mode:
		return false
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		return false
	if not root.input_state.is_idle():
		return false
	var scope: int = plugin.classify_selection_scope(plugin._current_selection_nodes(), root)
	return scope == SCOPE_NATIVE_ONLY


## The selection guard for a key that runs a command, asking what
## `HFCommandRegistry` says the command needs: the numbers and the label the
## palette, toolbar and menus ask with too, so a refusal reads the same from a
## key as from the palette (#1298). Rotate, Flip, Reset Rotation and Nudge pass
## their own numbers: the palette asks nothing of the selection for those, and a
## key does.
static func _registry_guard(plugin: Object, root: Node, action: String) -> int:
	var requirement: Dictionary = HFCommandRegistryType.selection(action)
	return plugin._guard_hammerforge_shortcut(
		root,
		bool(requirement.get("brushes_only", false)),
		int(requirement.get("minimum", 1)),
		str(requirement.get("label", HFCommandRegistryType.label(action)))
	)


## Run the command a key is with the settings its keymap entry carries, past the
## same selection guard as its arm, as a bound command runs (#1997). The
## command's mode is asked as the router asks it, so a paint key in paint mode
## comes first. SHORTCUT_APPLY when the key carries none, for its arm to run it.
static func _run_with_key_settings(
	plugin: Object, event: InputEventKey, root: Node, paint_mode: bool
) -> int:
	var keymap = plugin.get("_keymap")
	if keymap == null or not keymap.has_method("args_for"):
		return SHORTCUT_APPLY
	var mode := "vertex" if plugin.get("_vertex_mode") else ("paint" if paint_mode else "general")
	var action := HFPluginCommands.key_command(plugin, event, mode)
	if action == "" or not HFPluginCommands.takes_settings(action):
		return SHORTCUT_APPLY
	var settings: Dictionary = keymap.args_for(action)
	if settings.is_empty():
		return SHORTCUT_APPLY
	if not HFCommandRegistryType.selection(action).is_empty():
		var guard = _registry_guard(plugin, root, action)
		if guard != SHORTCUT_APPLY:
			return guard
	HFPluginCommands.execute(plugin, action, [], settings)
	return STOP


## Extrude from a key, the way its settings say.
static func _extrude(plugin: Object, root: Node, dock: Object, settings: Dictionary) -> void:
	plugin._prepare_tool_transition(root)
	dock.highlight_tab("Brush")
	plugin._deactivate_external_tool()
	dock.set_extrude_tool(HFPluginCommands.extrude_way(settings))
	plugin._update_hud_context()


static func handle_keyboard(
	plugin: Object, event: InputEventKey, root: Node, tool_id: int, paint_mode: bool
) -> int:
	if plugin == null or event == null or root == null:
		return PASS
	var answer := _handle_keyboard(plugin, event, root, tool_id, paint_mode)
	# For Repeat Last Command and the palette's recent list (#1694).
	if answer == STOP:
		var mode := (
			"vertex" if plugin.get("_vertex_mode") else ("paint" if paint_mode else "general")
		)
		HFPluginCommands.note_key_command(plugin, event, mode)
	return answer


static func _handle_keyboard(
	plugin: Object, event: InputEventKey, root: Node, tool_id: int, paint_mode: bool
) -> int:
	var dock = plugin.get("dock")
	var keymap = plugin.get("_keymap")

	if HFPluginShortcutsType.cancel_undo_preview(plugin, root, event):
		return STOP

	# Numeric input during drag/extrude
	if root.input_state.is_dragging() or root.input_state.is_extruding():
		var nr = plugin._handle_numeric_input(event, root)
		if nr != PASS:
			return nr

	# The palette's chords, Escape and the nudge keys are taken ahead of every
	# binding, so the keymap reports a binding on one as taken (#1614).
	var fixed := HFKeymapType.fixed_key(event)
	# Hotkey palette toggle (? = Shift+/ or F1 or Ctrl+K)
	if plugin._hotkey_palette:
		if plugin._hotkey_palette.visible and fixed == "cancel":
			plugin._hotkey_palette.visible = false
			return STOP
		if fixed == "command_palette":
			plugin._on_toggle_hotkey_palette()
			return STOP
	if fixed == "cancel":
		return STOP if plugin._cancel_escape_step(root) else PASS
	# Undo, Redo, Save and Run are Godot's whatever a binding says (#1617).
	if HFKeymapType.godot_editor_uses(event):
		return PASS
	if yields_to_godot(plugin, event, root, paint_mode):
		return PASS
	# High-level workflow shortcuts stay together so they remain predictable
	# regardless of the currently active draw/select/paint tool. They and the two
	# menus below answer ahead of the paint keys, and `HFKeymap.EVERY_MODE` lists
	# them so a paint key on one of their chords is reported.
	if keymap.matches("toggle_operation", event):
		plugin._on_context_toggle_operation()
		return STOP
	if keymap.matches("toggle_paint_mode", event):
		plugin._toggle_paint_mode()
		return STOP
	if keymap.matches("quick_play", event):
		if dock:
			dock._on_quick_play()
		return STOP
	if keymap.matches("validate_level", event):
		if dock:
			dock._on_validate_level()
		return STOP
	# A view switch, so it answers in every tool and mode.
	if keymap.matches("toggle_selection_size", event):
		if dock:
			dock.toggle_show_selection_size()
		return STOP
	# The Operation Replay timeline, also in every tool and mode. A binding, so it
	# can be moved and a clash with it is reported (#1608).
	if keymap.matches("toggle_operation_replay", event):
		HFPluginCommands.execute(plugin, "toggle_operation_replay")
		return STOP
	# The command line over the viewport, in every tool and mode (#1696).
	if keymap.matches("command_line", event):
		HFPluginCommands.execute(plugin, "command_line")
		return STOP

	# A distance typed along the guide the viewport shows, and Shift tracking a
	# point when the preferences say so (#1692). Only while a guide shows, or a
	# number is being typed, so a key goes on as before otherwise.
	if HFPluginSnapFeedbackType.key(plugin, event):
		return STOP
	# External tool keyboard dispatch first — external tools can override keys
	if plugin._tool_registry and plugin._tool_registry.has_active_external_tool():
		var ext_result = plugin._tool_registry.dispatch_keyboard(event)
		if ext_result == STOP:
			return ext_result
	# Tab steps the snap the viewport shows to the next kind in reach (#1691). A
	# typed number's Tab is asked above, and a tool's own Tab, such as the Clip
	# tool's side, just before; with no snap showing Tab goes on as before.
	if HFPluginSnapFeedbackType.step(plugin, event):
		return STOP

	# Viewport context menu — only when idle (no active operation, no active external tool)
	if keymap.matches("context_menu", event):
		var has_active_ext = (
			plugin._tool_registry and plugin._tool_registry.has_active_external_tool()
		)
		if root.input_state.is_idle() and not has_active_ext:
			plugin._show_viewport_context_menu(root, tool_id)
			return STOP
	# Radial menu toggle — same idle guard
	if keymap.matches("radial_menu", event):
		if plugin._radial_menu and is_instance_valid(plugin._radial_menu):
			if plugin._radial_menu.is_active():
				plugin._radial_menu.hide_menu()
				return STOP
			var radial_ext = (
				plugin._tool_registry and plugin._tool_registry.has_active_external_tool()
			)
			if root.input_state.is_idle() and not radial_ext:
				plugin._radial_menu.show_at(plugin._get_current_overlay_mouse_pos())
				return STOP
		else:
			plugin._toast_power_user_overlay_hint()
			return STOP

	# Double-tap detection for quick property popups (G G, B B, R R)
	# Must come before keymap matches so the second tap is intercepted.
	var tap_now := Time.get_ticks_msec()
	if not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
		if (
			event.keycode == plugin._last_tap_keycode
			and (tap_now - plugin._last_tap_time) < plugin._DOUBLE_TAP_MS
		):
			var handled = plugin._handle_double_tap(event.keycode, root, paint_mode)
			if handled:
				plugin._last_tap_keycode = 0
				return STOP
		plugin._last_tap_keycode = event.keycode
		plugin._last_tap_time = tap_now

	# A key whose keymap entry carries settings runs its command with them, ahead
	# of the arms below, which run it with the dock's (#1997).
	var with_settings := _run_with_key_settings(plugin, event, root, paint_mode)
	if with_settings != SHORTCUT_APPLY:
		return with_settings

	# Paint tool shortcuts, ahead of every general action below: paint mode owns
	# its keys while it is on, as vertex mode does, so a general action sharing a
	# chord with one waits for paint mode to end rather than leaving the paint key
	# dead (#1614).
	if paint_mode:
		if keymap.matches("paint_raise", event):
			plugin._begin_floor_paint_raise(root)
			return STOP
		if keymap.matches("paint_mirror_x", event):
			dock.toggle_paint_mirror_x()
			return STOP
		if keymap.matches("paint_mirror_z", event):
			dock.toggle_paint_mirror_z()
			return STOP
		if keymap.matches("paint_room", event):
			plugin._stamp_floor_paint_room(root)
			return STOP
		if keymap.matches("paint_confirm_connector", event):
			plugin._confirm_floor_paint_connector(root)
			return STOP
		var paint_key := -1
		if keymap.matches("paint_bucket", event):
			paint_key = 0
		elif keymap.matches("paint_erase", event):
			paint_key = 1
		elif keymap.matches("paint_ramp", event):
			paint_key = 2
		elif keymap.matches("paint_line", event):
			paint_key = 3
		elif keymap.matches("paint_fill", event):
			paint_key = 4
		elif keymap.matches("paint_blend", event):
			paint_key = 5
		if paint_key >= 0:
			dock.set_paint_tool(paint_key)
			return STOP

	if keymap.matches("delete", event):
		var delete_guard = _registry_guard(plugin, root, "delete")
		if delete_guard != SHORTCUT_APPLY:
			return delete_guard
		plugin._delete_selected(root)
		return STOP
	if keymap.matches("duplicate", event):
		var duplicate_guard = _registry_guard(plugin, root, "duplicate")
		if duplicate_guard != SHORTCUT_APPLY:
			return duplicate_guard
		plugin._duplicate_selected(root)
		return STOP
	if keymap.matches("copy", event):
		var copy_guard = _registry_guard(plugin, root, "copy")
		if copy_guard != SHORTCUT_APPLY:
			return copy_guard
		plugin._copy_selection(root)
		return STOP
	if keymap.matches("paste_at_cursor", event):
		var at_cursor_guard = _registry_guard(plugin, root, "paste_at_cursor")
		if at_cursor_guard != SHORTCUT_APPLY:
			return at_cursor_guard
		HFPluginEditActionsType.paste_at_cursor(plugin, root)
		return STOP
	if keymap.matches("paste", event):
		# Nothing has to be selected to paste, so the guard asks for none. It is
		# still asked, because the answer also says whether this selection is
		# HammerForge's to act on at all.
		var paste_guard = _registry_guard(plugin, root, "paste")
		if paste_guard != SHORTCUT_APPLY:
			return paste_guard
		plugin._paste_clipboard(root)
		return STOP
	if keymap.matches("group", event):
		var group_guard = _registry_guard(plugin, root, "group")
		if group_guard != SHORTCUT_APPLY:
			return group_guard
		plugin._group_selected(root)
		return STOP
	if keymap.matches("ungroup", event):
		var ungroup_guard = _registry_guard(plugin, root, "ungroup")
		if ungroup_guard != SHORTCUT_APPLY:
			return ungroup_guard
		plugin._ungroup_selected(root)
		return STOP
	if keymap.matches("hollow", event):
		var hollow_guard = _registry_guard(plugin, root, "hollow")
		if hollow_guard != SHORTCUT_APPLY:
			return hollow_guard
		plugin._hollow_selected(root)
		return STOP
	if keymap.matches("hide_selection", event):
		var hide_guard = _registry_guard(plugin, root, "hide_selection")
		if hide_guard != SHORTCUT_APPLY:
			return hide_guard
		HFPluginViewCommandsType.hide_selection(plugin, root)
		return STOP
	# Nothing has to be selected to bring hidden things back.
	if keymap.matches("show_hidden", event):
		if root == null:
			return PASS
		HFPluginViewCommandsType.show_hidden(plugin, root)
		return STOP
	if keymap.matches("move_to_floor", event):
		var floor_guard = _registry_guard(plugin, root, "move_to_floor")
		if floor_guard != SHORTCUT_APPLY:
			return floor_guard
		plugin._move_selected_to_floor(root)
		return STOP
	if keymap.matches("move_to_ceiling", event):
		var ceiling_guard = _registry_guard(plugin, root, "move_to_ceiling")
		if ceiling_guard != SHORTCUT_APPLY:
			return ceiling_guard
		plugin._move_selected_to_ceiling(root)
		return STOP
	# Whole brushes only outside vertex mode. In it the chord is Snap Vertices to
	# Grid's, which the vertex input answers before this router is asked.
	if keymap.matches("snap_to_grid", event) and not plugin._vertex_mode:
		var snap_guard = _registry_guard(plugin, root, "snap_to_grid")
		if snap_guard != SHORTCUT_APPLY:
			return snap_guard
		HFPluginEditActionsType.snap_selected_to_grid(plugin, root)
		return STOP
	if keymap.matches("clip", event):
		var clip_guard = _registry_guard(plugin, root, "clip")
		if clip_guard != SHORTCUT_APPLY:
			return clip_guard
		plugin._clip_selected(root)
		return STOP
	# No selection guard: Face Select empties the object selection by design, and
	# the command reads the objects that were selected on the way in. Its own
	# messages say what is missing.
	if keymap.matches("clip_to_face", event):
		if root == null:
			return PASS
		plugin._clip_to_face_plane_selected(root)
		return STOP
	# The same for a Trim Run: it reads the faces picked in Face Select (#1414).
	if keymap.matches("run_trim_along_faces", event):
		if root == null:
			return PASS
		HFPluginEditActionsType.run_trim_along_faces(plugin, root)
		return STOP
	if keymap.matches("carve", event):
		var carve_guard = _registry_guard(plugin, root, "carve")
		if carve_guard != SHORTCUT_APPLY:
			return carve_guard
		plugin._carve_selected(root)
		return STOP
	if keymap.matches("merge", event):
		var merge_guard = _registry_guard(plugin, root, "merge")
		if merge_guard != SHORTCUT_APPLY:
			return merge_guard
		plugin._merge_selected(root)
		return STOP
	if keymap.matches("intersect", event):
		var intersect_guard = _registry_guard(plugin, root, "intersect")
		if intersect_guard != SHORTCUT_APPLY:
			return intersect_guard
		plugin._intersect_selected(root)
		return STOP
	# Create Structure needs a level and the dock that holds the settings, but no
	# selection: with nothing selected it builds at the world origin.
	if keymap.matches("create_arch", event):
		if root == null or dock == null:
			return PASS
		dock._on_create_structure()
		return STOP
	for action in ["grid_up", "grid_down", "grid_reset", "grid_align"]:
		if keymap.matches(action, event):
			HFPluginCommands.execute(plugin, action)
			return STOP
	# Nudge keys. Alt makes the step a tenth of the grid's, for the fitting the
	# grid cannot reach, and a tenth is never put back on the grid (#1431). Alt
	# with PgUp/PgDn alone moves the drawing plane, above, so a vertical tenth
	# takes Shift as well. Ctrl+Arrow is the shortcut stage's.
	# Shift with an arrow duplicates the selection and moves the copy one step
	# that way, and Alt makes the step a tenth (#1716). It was a plain nudge with
	# Shift ignored. Shift with Page Up or Down stays a nudge, for the vertical
	# tenth Alt+Shift gives.
	# In Face Select with faces picked, the arrows slide and turn their textures
	# (#1728). Face Select puts the object selection aside, so a nudge had nothing
	# to move there.
	if (
		fixed == "nudge"
		and not event.ctrl_pressed
		and HFPluginTextureKeysType.handle(plugin, root, event)
	):
		return STOP
	if fixed == "nudge" and event.shift_pressed and not event.ctrl_pressed:
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var copy_guard = plugin._guard_hammerforge_shortcut(
				root, false, 1, "Duplicate and Move"
			)
			if copy_guard != SHORTCUT_APPLY:
				return copy_guard
			HFPluginEditActionsType.duplicate_and_move(
				plugin,
				root,
				(
					plugin._get_nudge_direction(event.keycode)
					* (FINE_NUDGE if event.alt_pressed else 1.0)
				)
			)
			return STOP
	if fixed == "nudge" and not event.ctrl_pressed:
		var nudge = plugin._get_nudge_direction(event.keycode)
		var nudge_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Nudge")
		if nudge_guard != SHORTCUT_APPLY:
			return nudge_guard
		plugin._nudge_selected(root, nudge * (FINE_NUDGE if event.alt_pressed else 1.0))
		return STOP
	# Grid snap size shortcuts ([ = halve, ] = double)
	if keymap.matches("grid_decrease", event):
		plugin._adjust_grid_snap(root, 0.5)
		return STOP
	if keymap.matches("grid_increase", event):
		plugin._adjust_grid_snap(root, 2.0)
		return STOP
	# Repeat Last Brush: a stamp of the brush the last Draw made (#1407).
	if keymap.matches("repeat_brush", event):
		HFPluginCommands.execute(plugin, "repeat_brush")
		return STOP
	# Tool switch shortcuts
	if keymap.matches("tool_draw", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		if dock.tool_draw:
			dock.tool_draw.button_pressed = true
		plugin._update_hud_context()
		return STOP
	if keymap.matches("tool_select", event):
		plugin._prepare_tool_transition(root)
		dock.highlight_tab("Brush")
		plugin._deactivate_external_tool()
		if dock.tool_select:
			dock.tool_select.button_pressed = true
		plugin._update_hud_context()
		return STOP
	# Extrude is one command with a Direction. Its old ids run it with theirs, and
	# a keymap entry's `args` set it too (#1867).
	for extrude_id in ["tool_extrude_up", "tool_extrude_down"]:
		if keymap.matches(extrude_id, event):
			_extrude(plugin, root, dock, HFPluginCommands.key_settings(extrude_id, keymap))
			return STOP
	# E / Shift+E for extrude (Blender convention) — skip in paint and vertex modes
	if not paint_mode and not plugin._vertex_mode:
		for extrude_id in ["tool_extrude", "tool_extrude_down_alt"]:
			if keymap.matches(extrude_id, event):
				_extrude(plugin, root, dock, HFPluginCommands.key_settings(extrude_id, keymap))
				return STOP
	# Texture picker (eyedropper) — T key activates click-to-sample mode
	if keymap.matches("texture_picker", event):
		plugin._texture_picker_active = true
		if dock:
			dock.show_toast("Texture Picker: click a face to sample its material", 0)
		return STOP
	# Apply Last Texture — Shift+T reapplies the last picked material
	if keymap.matches("apply_last_texture", event):
		var has_selected_faces: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_selected_faces:
			var texture_guard = _registry_guard(plugin, root, "apply_last_texture")
			if texture_guard != SHORTCUT_APPLY:
				return texture_guard
		plugin._apply_last_texture(root)
		return STOP
	# Apply Picked Look — Alt+T gives the selected faces the whole look T read.
	# It works on faces alone, so the dock judges the selection and says what it
	# wants, a pick or faces, where the brush guard could only ask for brushes.
	if keymap.matches("apply_picked_look", event):
		if dock:
			dock._on_apply_picked_look()
		return STOP
	# Apply Favorite N — Alt+1 to Alt+9 give the selection the context toolbar's
	# favourite N. Never reached mid-draw: the numeric entry above keeps the digit.
	for slot in range(1, HFMaterialBrowserType.FAVORITE_SLOTS + 1):
		var favorite_action := "apply_favorite_%d" % slot
		if not keymap.matches(favorite_action, event):
			continue
		if not (root.face_selection is Dictionary and not root.face_selection.is_empty()):
			var favorite_guard = _registry_guard(plugin, root, favorite_action)
			if favorite_guard != SHORTCUT_APPLY:
				return favorite_guard
		HFPluginMaterialCommandsType.apply_favorite(plugin, slot)
		return STOP
	# Select Similar — Shift+S selects matching faces/brushes
	if keymap.matches("select_similar", event):
		var has_similar_face_source: bool = (
			root.face_selection is Dictionary and not root.face_selection.is_empty()
		)
		if not has_similar_face_source:
			var similar_guard = _registry_guard(plugin, root, "select_similar")
			if similar_guard != SHORTCUT_APPLY:
				return similar_guard
		plugin._select_similar(root)
		return STOP
	# Grow / Shrink Selection — Ctrl+] and Ctrl+[, on the faces when any are
	# picked, which Face Select leaves with no object selection to guard.
	for grow_action in ["grow_selection", "shrink_selection"]:
		if not keymap.matches(grow_action, event):
			continue
		if not (root.face_selection is Dictionary and not root.face_selection.is_empty()):
			var grow_guard = _registry_guard(plugin, root, grow_action)
			if grow_guard != SHORTCUT_APPLY:
				return grow_guard
		if grow_action == "grow_selection":
			HFPluginSelectionCommandsType.grow_selection(plugin, root)
		else:
			HFPluginSelectionCommandsType.shrink_selection(plugin, root)
		return STOP
	# Face X-ray — Alt+X flips the checkbox beside Face Select Mode
	if keymap.matches("toggle_face_xray", event):
		HFPluginSelectionCommandsType.toggle_face_xray(plugin)
		return STOP
	# Selection Filter popup — Alt+F opens the filter popover
	if keymap.matches("selection_filter", event):
		var filter_scope = plugin.classify_selection_scope(plugin._current_selection_nodes(), root)
		# plugin.SelectionScope: EMPTY=0, NATIVE_ONLY=1, HAMMERFORGE_ONLY=2, MIXED=3
		if filter_scope == 1:
			return PASS
		if filter_scope == 3:
			if dock:
				dock.show_toast("Edit HammerForge and Godot nodes separately", 1)
			return STOP
		plugin._show_selection_filter()
		return STOP
	# Select All / Deselect All — A / Shift+A (Blender convention)
	if keymap.matches("select_all", event):
		plugin._select_all_nodes(root)
		return STOP
	if keymap.matches("deselect_all", event):
		plugin._deselect_all_nodes(root)
		return STOP
	# Quick Save as Prefab
	if keymap.matches("quick_save_prefab", event):
		var save_prefab_guard = _registry_guard(plugin, root, "quick_save_prefab")
		if save_prefab_guard != SHORTCUT_APPLY:
			return save_prefab_guard
		plugin._quick_save_prefab(root, false)
		return STOP
	# Cycle Prefab Variant
	if keymap.matches("cycle_variant", event):
		var variant_guard = _registry_guard(plugin, root, "cycle_variant")
		if variant_guard != SHORTCUT_APPLY:
			return variant_guard
		plugin._cycle_prefab_variant(root)
		return STOP
	# Draw on Face. Below the paint shortcuts, where L is the Line tool.
	if not paint_mode and keymap.matches("toggle_draw_on_face", event):
		HFPluginCommands.execute(plugin, "toggle_draw_on_face")
		return STOP
	# Free transform. The whole block sits below the paint shortcuts and is gated
	# on paint mode being off, because R is bound to both `rotate_ccw` and
	# `paint_ramp`. Gating the group rather than just R keeps the family
	# consistent: in paint mode none of them fire.
	if not paint_mode:
		if keymap.matches("rotate_ccw", event):
			var rotate_ccw_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Rotate")
			if rotate_ccw_guard != SHORTCUT_APPLY:
				return rotate_ccw_guard
			plugin._rotate_selected(root, 1)
			return STOP
		if keymap.matches("rotate_cw", event):
			var rotate_cw_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Rotate")
			if rotate_cw_guard != SHORTCUT_APPLY:
				return rotate_cw_guard
			plugin._rotate_selected(root, -1)
			return STOP
		if keymap.matches("flip_selection", event):
			var flip_guard = plugin._guard_hammerforge_shortcut(root, false, 1, "Flip")
			if flip_guard != SHORTCUT_APPLY:
				return flip_guard
			plugin._flip_selected(root)
			return STOP
		if keymap.matches("mirror_copy", event):
			var mirror_guard = _registry_guard(plugin, root, "mirror_copy")
			if mirror_guard != SHORTCUT_APPLY:
				return mirror_guard
			HFPluginEditActionsType.mirror_copy_selected(plugin, root)
			return STOP
		if keymap.matches("reset_rotation", event):
			var reset_guard = plugin._guard_hammerforge_shortcut(root, true, 1, "Reset Rotation")
			if reset_guard != SHORTCUT_APPLY:
				return reset_guard
			plugin._reset_rotation_selected(root)
			return STOP
		# Faces picked in Face Select are what Offset moves then, with no object
		# selected, so the guard is asked only without them, as Select Similar's is.
		# Mid-draw it does nothing: the typed numbers are the draw's.
		if keymap.matches("offset_selection", event):
			var has_offset_faces: bool = (
				root.face_selection is Dictionary and not root.face_selection.is_empty()
			)
			if not has_offset_faces:
				var offset_guard = _registry_guard(plugin, root, "offset_selection")
				if offset_guard != SHORTCUT_APPLY:
					return offset_guard
			HFPluginTransformToolsType.open_offset(plugin, root)
			return STOP
		if keymap.matches("pick_pivot", event):
			HFPluginTransformToolsType.arm_pivot_pick(plugin, root)
			return STOP
		if keymap.matches("clear_pivot", event):
			HFPluginTransformToolsType.clear_pivot(plugin, root)
			return STOP
	# Axis lock for construction tools and Select's vertex-edit operation.
	if plugin.axis_lock_shortcuts_available(tool_id, plugin._vertex_mode):
		if keymap.matches("axis_x", event):
			root.set_axis_lock(LevelRootType.AxisLock.X, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.X)
			return STOP
		if keymap.matches("axis_y", event):
			root.set_axis_lock(LevelRootType.AxisLock.Y, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Y)
			return STOP
		if keymap.matches("axis_z", event):
			root.set_axis_lock(LevelRootType.AxisLock.Z, true)
			plugin._update_hud_context()
			if dock:
				dock.update_axis_lock_buttons(LevelRootType.AxisLock.Z)
			return STOP
	# Vertex edit toggle (V key)
	if keymap.matches("vertex_edit", event):
		var vertex_guard = _registry_guard(plugin, root, "vertex_edit")
		if vertex_guard != SHORTCUT_APPLY:
			return vertex_guard
		plugin._toggle_vertex_mode(root)
		plugin._show_coach_mark_for_action("vertex_edit")
		return STOP
	# External tool shortcuts
	if plugin._tool_registry:
		var ext_id = plugin._tool_registry.check_shortcut(event, keymap)
		if ext_id >= 0 and plugin.active_root:
			plugin._activate_external_tool(ext_id, plugin.active_root)
			plugin._show_coach_mark_for_tool_id(ext_id)
			plugin._update_hud_context()
			return STOP
	# A command with no key of its own, given one in the shortcut dialog, runs as
	# the palette runs it, past the same selection guard (#1733).
	var bound: String = keymap.user_bound_command(event) if keymap else ""
	if bound != "":
		if not HFCommandRegistryType.selection(bound).is_empty():
			var bound_guard = _registry_guard(plugin, root, bound)
			if bound_guard != SHORTCUT_APPLY:
				return bound_guard
		HFPluginCommands.execute(plugin, bound, [], keymap.args_for(bound))
		return STOP
	return PASS
