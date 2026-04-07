@tool
extends PanelContainer
## First-run welcome panel showing a quick-start guide.

signal dismissed(dont_show_again: bool)

var _dont_show: CheckBox


func _ready() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title = Label.new()
	title.text = "Welcome to HammerForge"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var steps := [
		["1.", "Add a LevelRoot node to your scene (or one will be created automatically)."],
		[
			"2.",
			(
				"Use Draw (D) to click + drag brushes in the viewport. "
				+ "If the scene is empty, use Manage > Create Floor first."
			),
		],
		["3.", "Switch to Select (S) to move, resize, and modify brushes."],
		["4.", "Open the Paint tab to texture your surfaces."],
		["5.", "Go to Manage > Bake to convert brushes into final geometry."],
	]

	for step in steps:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var num = Label.new()
		num.text = step[0]
		num.add_theme_font_size_override("font_size", 13)
		num.custom_minimum_size = Vector2(18, 0)
		row.add_child(num)
		var desc = Label.new()
		desc.text = step[1]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc)
		vbox.add_child(row)

	var tip = Label.new()
	tip.text = "Press ? in the toolbar to see all keyboard shortcuts."
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tip)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var bottom = HBoxContainer.new()
	vbox.add_child(bottom)

	_dont_show = CheckBox.new()
	_dont_show.text = "Don't show again"
	_dont_show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_dont_show)

	var close_btn = Button.new()
	close_btn.text = "Get Started"
	close_btn.pressed.connect(_on_close)
	bottom.add_child(close_btn)


func _on_close() -> void:
	dismissed.emit(_dont_show.button_pressed)
