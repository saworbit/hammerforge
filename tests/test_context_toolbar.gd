extends GutTest

const HFViewportContextMenu = preload("res://addons/hammerforge/ui/hf_viewport_context_menu.gd")

const HFContextToolbar = preload("res://addons/hammerforge/ui/hf_context_toolbar.gd")

var toolbar: HFContextToolbar


func before_each():
	toolbar = HFContextToolbar.new()
	add_child_autoqfree(toolbar)


func after_each():
	toolbar = null


# ===========================================================================
# Context determination
# ===========================================================================


func test_no_root_yields_none():
	toolbar.update_state({"has_root": false})
	assert_false(toolbar.visible)


func test_brush_selected_shows_toolbar():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 1,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_true(toolbar.visible)


func test_context_brush_selected():
	var state = {
		"has_root": true,
		"brush_count": 2,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.BRUSH_SELECTED)


func test_context_face_selected():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 3,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.FACE_SELECTED)


func test_context_entity_selected():
	var state = {
		"has_root": true,
		"brush_count": 0,
		"entity_count": 1,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.ENTITY_SELECTED)


func test_context_draw_idle():
	var state = {
		"has_root": true,
		"brush_count": 0,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 0,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.DRAW_IDLE)


func test_context_dragging():
	var state = {
		"has_root": true,
		"brush_count": 0,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 1,
		"tool": 0,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.DRAGGING)


func test_context_vertex_edit():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 5,
		"tool": 1,
		"vertex_mode": true,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.VERTEX_EDIT)


func test_hidden_when_no_context():
	var state = {
		"has_root": true,
		"brush_count": 0,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.NONE)
	assert_false(toolbar.visible)


func test_mixed_native_and_hammerforge_selection_hides_managed_toolbar():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"mixed_selection": true,
	}
	toolbar.update_state(state)
	assert_eq(toolbar._context, HFContextToolbar.Context.NONE)
	assert_false(toolbar.visible)


# ===========================================================================
# Action signals
# ===========================================================================


func test_action_signal_emitted():
	var received := []
	toolbar.action_requested.connect(func(action, args): received.append(action))
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 1,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	# Find the Hollow button and press it
	var section = toolbar._sections[HFContextToolbar.Context.BRUSH_SELECTED]
	for child in section.get_children():
		if child is Button and child.text == "Hol":
			child.emit_signal("pressed")
			break
	assert_has(received, "hollow")


func test_operation_toggle_draw_section():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 0,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 0,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	var section = toolbar._sections[HFContextToolbar.Context.DRAW_IDLE]
	var toggle = section.get_node_or_null("OpToggle")
	assert_not_null(toggle)
	assert_eq(toggle.text, "Add")


func test_subtract_mode_updates_toggle():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 0,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 0,
				"vertex_mode": false,
				"is_subtract": true,
			}
		)
	)
	var section = toolbar._sections[HFContextToolbar.Context.DRAW_IDLE]
	var toggle = section.get_node_or_null("OpToggle")
	assert_eq(toggle.text, "Sub")


# ===========================================================================
# Label content
# ===========================================================================


func test_brush_label_singular():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 1,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_eq(toolbar._label.text, "1 brush selected")


func test_brush_label_plural():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 5,
				"entity_count": 0,
				"face_count": 0,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_eq(toolbar._label.text, "5 brushes selected")


func test_brush_label_refreshes_without_context_change():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"is_subtract": false,
	}
	toolbar.update_state(state)
	state["brush_count"] = 4
	toolbar.update_state(state)
	assert_eq(toolbar._label.text, "4 brushes selected")


func test_prefab_badge_and_buttons_refresh_without_context_change():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
	}
	toolbar.update_state(state)
	var section = toolbar._sections[HFContextToolbar.Context.BRUSH_SELECTED]
	assert_false(section.get_node("PfbVarBtn").visible)

	state["prefab_source"] = "res://prefabs/door.tres"
	state["prefab_variant"] = "damaged"
	state["prefab_linked"] = true
	toolbar.update_state(state)

	assert_eq(toolbar._label.text, "door (damaged) [linked]")
	for child_name in ["PfbSep", "PfbVarBtn", "PfbPushBtn", "PfbPullBtn"]:
		assert_true(section.get_node(child_name).visible, "%s should be visible" % child_name)

	state.erase("prefab_source")
	state.erase("prefab_variant")
	state.erase("prefab_linked")
	toolbar.update_state(state)

	assert_eq(toolbar._label.text, "1 brush selected")
	for child_name in ["PfbSep", "PfbVarBtn", "PfbPushBtn", "PfbPullBtn"]:
		assert_false(section.get_node(child_name).visible, "%s should be hidden" % child_name)


func test_brush_buttons_refresh_without_context_change():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
		"bake_preview_active": false,
		"bake_disabled": false,
	}
	toolbar.update_state(state)
	var section = toolbar._sections[HFContextToolbar.Context.BRUSH_SELECTED]
	var preview_btn = section.get_node("BakePreviewBtn") as Button
	assert_false(preview_btn.button_pressed)
	assert_false(preview_btn.disabled)

	state["bake_preview_active"] = true
	state["bake_disabled"] = true
	toolbar.update_state(state)

	assert_true(preview_btn.button_pressed)
	assert_true(preview_btn.disabled)


func test_hint_bar_and_content_share_vertical_layout():
	assert_true(toolbar._layout is VBoxContainer)
	assert_eq(toolbar._content.get_parent(), toolbar._layout)
	assert_eq(toolbar._auto_hint_bar.get_parent(), toolbar._layout)
	assert_eq(toolbar._layout.get_child(0), toolbar._content)
	assert_eq(toolbar._layout.get_child(1), toolbar._auto_hint_bar)


func test_face_label():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"brush_count": 1,
				"entity_count": 0,
				"face_count": 3,
				"input_mode": 0,
				"tool": 1,
				"vertex_mode": false,
				"is_subtract": false,
			}
		)
	)
	assert_eq(toolbar._label.text, "3 faces on 1 brush")


# ===========================================================================
# Material thumbnails
# ===========================================================================


func test_set_favorite_materials():
	(
		toolbar
		. set_favorite_materials(
			[
				{"index": 0, "name": "Brick"},
				{"index": 1, "name": "Concrete"},
			]
		)
	)
	assert_true(toolbar._material_thumbs[0].visible)
	assert_true(toolbar._material_thumbs[1].visible)
	assert_false(toolbar._material_thumbs[2].visible)


func test_material_quick_apply_signal():
	var received := []
	toolbar.material_quick_apply.connect(func(idx): received.append(idx))
	(
		toolbar
		. set_favorite_materials(
			[
				{"index": 5, "name": "Metal"},
			]
		)
	)
	toolbar._on_material_thumb(0)
	assert_eq(received, [5])


func test_viewport_menu_context_matches_selection_state():
	var menu = HFViewportContextMenu.new()
	add_child(menu)
	assert_eq(menu._determine_context({"vertex_mode": true}), menu.Context.VERTEX_EDIT)
	assert_eq(menu._determine_context({"face_count": 2}), menu.Context.FACE_SELECTED)
	assert_eq(menu._determine_context({"entity_count": 1}), menu.Context.ENTITY_SELECTED)
	assert_eq(menu._determine_context({"brush_count": 1}), menu.Context.BRUSH_SELECTED)
	assert_eq(menu._determine_context({"tool": 0, "input_mode": 0}), menu.Context.DRAW_IDLE)
	assert_eq(menu._determine_context({"tool": 1, "input_mode": 0}), menu.Context.NONE)
	assert_eq(
		menu._determine_context({"mixed_selection": true, "brush_count": 1}),
		menu.Context.NONE,
	)
	(
		menu
		. show_at(
			Vector2.ZERO,
			{
				"mixed_selection": true,
				"brush_count": 1,
				"tool": 1,
				"input_mode": 0,
			},
		)
	)
	assert_eq(menu.get_item_text(0), "Edit HammerForge and Godot nodes separately")
	assert_true(menu.is_item_disabled(0))
	menu.hide()
	menu.free()
