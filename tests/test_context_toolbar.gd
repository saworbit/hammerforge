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


func test_floor_paint_has_a_generative_context_toolbar():
	(
		toolbar
		. update_state(
			{
				"has_root": true,
				"paint_mode": true,
				"paint_mirror_x": true,
				"paint_mirror_z": false,
				"mixed_selection": false,
			}
		)
	)
	assert_eq(toolbar._context, HFContextToolbar.Context.PAINT)
	assert_true(toolbar.visible)
	assert_true(toolbar._label.text.contains("Mirror X"))
	assert_true(toolbar._sections[HFContextToolbar.Context.PAINT].visible)


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
	assert_eq(toggle.text, "Solid")


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
	assert_eq(toggle.text, "Cut")


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


func test_structure_buttons_show_for_a_piece_of_a_structure():
	var state = {
		"has_root": true,
		"brush_count": 1,
		"entity_count": 0,
		"face_count": 0,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
	}
	var names := ["StrSep", "StrUpdBtn", "StrDetBtn"]
	toolbar.update_state(state)
	var section = toolbar._sections[HFContextToolbar.Context.BRUSH_SELECTED]
	for child_name in names:
		assert_false(
			section.get_node(child_name).visible, "%s hidden for a plain brush" % child_name
		)

	state["structure_type"] = "stairs"
	toolbar.update_state(state)
	for child_name in names:
		assert_true(section.get_node(child_name).visible, "%s shown for a piece" % child_name)
	var sent: Array = []
	toolbar.action_requested.connect(func(action: String, _args: Array): sent.append(action))
	section.get_node("StrUpdBtn").pressed.emit()
	section.get_node("StrDetBtn").pressed.emit()
	assert_eq(sent, ["update_structure", "detach_structure"])

	state.erase("structure_type")
	toolbar.update_state(state)
	for child_name in names:
		assert_false(section.get_node(child_name).visible, "%s hidden again" % child_name)


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


func _nine_favourites() -> Array:
	var infos: Array = []
	for i in range(9):
		infos.append({"index": 10 + i, "name": "Fav %d" % (i + 1)})
	return infos


## The strip grew from five to nine, one for each of Alt+1 to Alt+9 (#1439), and
## button N is the browser's favourite N.
func test_the_favourites_strip_holds_nine_numbered_in_the_browsers_order():
	toolbar.set_favorite_materials(_nine_favourites())
	assert_eq(toolbar._material_thumbs.size(), 9)
	var received := []
	toolbar.material_quick_apply.connect(func(idx): received.append(idx))
	for i in range(9):
		var btn: Button = toolbar._material_thumbs[i]
		assert_true(btn.visible, "button %d shows" % (i + 1))
		assert_eq(btn.text, str(i + 1), "numbered as its slot")
		assert_string_contains(btn.tooltip_text, "Fav %d" % (i + 1), "naming the material")
		assert_string_contains(btn.tooltip_text, "Alt+%d" % (i + 1), "and the key that applies it")
		toolbar._on_material_thumb(i)
	assert_eq(received, [10, 11, 12, 13, 14, 15, 16, 17, 18], "each applies its own favourite")


func _state(face_count: int, brush_count: int, entity_count := 0) -> Dictionary:
	return {
		"has_root": true,
		"brush_count": brush_count,
		"entity_count": entity_count,
		"face_count": face_count,
		"input_mode": 0,
		"tool": 1,
		"vertex_mode": false,
	}


## A favourite goes on the selected faces or else the selected brushes, so the
## strip shows for either. It used to belong to the face section alone.
func test_the_favourites_strip_shows_for_faces_and_for_brushes():
	toolbar.set_favorite_materials(_nine_favourites())
	toolbar.update_state(_state(3, 1))
	assert_true(toolbar._favorites_strip.visible, "for selected faces")
	toolbar.update_state(_state(0, 2))
	assert_true(toolbar._favorites_strip.visible, "for selected brushes")
	toolbar.update_state(_state(0, 0, 1))
	assert_false(toolbar._favorites_strip.visible, "not for entities")
	toolbar.update_state(_state(0, 2))
	toolbar.set_favorite_materials([])
	assert_false(toolbar._favorites_strip.visible, "nor with no favourite to show")


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


func test_viewport_menu_offers_the_prefab_selected_in_the_library():
	var menu = HFViewportContextMenu.new()
	add_child(menu)
	var state := {"has_root": true, "tool": 1, "input_mode": 0}
	menu.show_at(Vector2.ZERO, state)
	assert_eq(menu.get_item_index(menu._ID_PLACE_PREFAB), -1, "nothing selected, nothing offered")
	menu.hide()
	state["library_prefab"] = "res://prefabs/crate.hfprefab"
	menu.show_at(Vector2.ZERO, state)
	var at: int = menu.get_item_index(menu._ID_PLACE_PREFAB)
	assert_gt(at, -1, "the selected prefab is offered")
	if at > -1:
		assert_eq(menu.get_item_text(at), "Place crate Here")
	var sent: Array = []
	menu.action_requested.connect(func(action: String, _args: Array): sent.append(action))
	menu._on_id_pressed(menu._ID_PLACE_PREFAB)
	assert_eq(sent, ["place_prefab"])
	menu.hide()
	menu.free()


# --- the row wraps rather than running off the viewport -------------------


func test_sections_wrap_instead_of_overflowing():
	# An HBoxContainer section runs off the sides of the viewport once the
	# buttons no longer fit. Measured before this: 940px of brush tools with the
	# viewport at 975px, and narrower than that with a dock open.
	for ctx_key in toolbar._sections:
		var section: Control = toolbar._sections[ctx_key]
		assert_true(
			section is FlowContainer,
			"Section %s cannot wrap, so it overflows instead" % str(ctx_key)
		)
		assert_eq(section.size_flags_horizontal, Control.SIZE_EXPAND_FILL)


func test_natural_row_width_reports_the_unwrapped_content():
	# A wrapping container reports only its widest child as a minimum, so the
	# placement code cannot ask it how wide the content really is.
	toolbar.update_state({"has_root": true, "brush_count": 1, "tool": 1})
	var natural: float = toolbar.natural_row_width()
	assert_gt(natural, 0.0)
	assert_gt(
		natural,
		toolbar.get_combined_minimum_size().x,
		"A wrapped row's minimum is one button wide; the natural width is the whole row"
	)
