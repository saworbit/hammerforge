@tool
class_name HFPluginBakePreview
extends RefCounted
## Owner of the wireframe bake-preview toggle state.
##
## Two flags on the plugin describe it. `_bake_preview_active` is what the toolbar
## shows. `_bake_preview_in_flight` marks a bake this module started, so the undo
## handler can tell our own commit apart from the user pressing Ctrl+Z.
##
## Every read and write of both flags goes through here, because the toggle is set
## speculatively before an async bake and has to be walked back when the bake fails
## or the scene is undone out from under it.

## PreviewMode.WIREFRAME. The only mode the toolbar toggle represents; Proxy is
## reachable from the dock dropdown but does not light the toggle.
const WIREFRAME_MODE := 1


## React to a bake finishing anywhere in the editor, ours or not.
static func on_bake_state_changed(plugin: Object, baking: bool, success: bool) -> void:
	if not baking:
		if plugin._bake_preview_in_flight:
			plugin._bake_preview_in_flight = false
			if not success:
				# The toggle speculatively set _bake_preview_active before
				# dispatching. Bake failed so baked_container is unchanged —
				# flip the flag back to match the actual scene.
				plugin._bake_preview_active = not plugin._bake_preview_active
			# On success the speculative value is correct — keep it.
		elif success:
			# A non-preview bake replaced baked_container. Derive the toggle
			# from the actual preview mode that was baked — the dock dropdown
			# may have been set to Wireframe for a normal bake.
			var root = plugin.active_root if plugin.active_root else plugin._get_level_root()
			if root:
				plugin._bake_preview_active = root._last_bake_preview_mode == WIREFRAME_MODE
			else:
				plugin._bake_preview_active = false
		# Non-preview bake failed: baked_container untouched, keep current flag.
	plugin._update_hud_context()


## Turn the wireframe preview on or off by re-baking at the matching quality.
##
## The bake is awaited directly rather than dispatched through UndoRedo: an async
## action cannot be replayed by the undo system, so routing it there would record
## a step that does nothing on redo.
static func toggle(plugin: Object, root: Node, pressed: bool) -> void:
	if not root or not root.bake_system:
		return
	# Guard against overlapping bakes.
	if (
		(plugin.dock and plugin.dock._bake_disabled)
		or (root.has_method("is_bake_in_flight") and root.call("is_bake_in_flight"))
	):
		plugin._update_hud_context()
		return
	var preview_mode: int = WIREFRAME_MODE if pressed else 0
	plugin._bake_preview_active = pressed
	plugin._bake_preview_in_flight = true
	if plugin.dock:
		plugin.dock._set_bake_buttons_disabled(true)
	var succeeded: bool = await root.bake(false, false, 0, preview_mode)
	if plugin.dock:
		plugin.dock._set_bake_buttons_disabled(false)
	if plugin._bake_preview_in_flight:
		plugin._bake_preview_in_flight = false
		if not succeeded:
			plugin._bake_preview_active = not pressed
	plugin._update_hud_context()


## Bring the toggle back in line with the scene after an undo or redo.
##
## Skipped while one of our own preview bakes is in flight, because that
## version_changed came from our commit rather than from the user.
static func sync_after_undo(plugin: Object, root: Node) -> void:
	if plugin._bake_preview_in_flight:
		return
	var restored: bool = root._last_bake_preview_mode == WIREFRAME_MODE
	if plugin._bake_preview_active != restored:
		plugin._bake_preview_active = restored
		plugin._update_hud_context()
