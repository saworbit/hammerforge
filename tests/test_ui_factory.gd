extends GutTest

const HFUIFactory = preload("res://addons/hammerforge/ui/hf_ui_factory.gd")


func test_make_spin_sets_range_and_default():
	var s = HFUIFactory.make_spin(0.0, 100.0, 0.5, 25.0)
	assert_not_null(s)
	assert_eq(s.min_value, 0.0)
	assert_eq(s.max_value, 100.0)
	assert_eq(s.step, 0.5)
	assert_eq(s.value, 25.0)
	assert_eq(s.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	s.free()


func test_make_spin_clamps_negative_default():
	# Critical: SpinBox defaults to [0,100]. Range must be set BEFORE value
	# or the value gets silently clamped.  HFUIFactory must do it in order.
	var s = HFUIFactory.make_spin(-1000.0, 1000.0, 1.0, -500.0)
	assert_eq(s.value, -500.0, "negative defaults must survive after range set")
	s.free()


func test_make_check():
	var c = HFUIFactory.make_check("Enable", true)
	assert_eq(c.text, "Enable")
	assert_true(c.button_pressed)
	c.free()

	var c2 = HFUIFactory.make_check("Disabled")
	assert_false(c2.button_pressed, "default_on=false by default")
	c2.free()


func test_make_button_with_tooltip():
	var b = HFUIFactory.make_button("Click", "Tooltip text")
	assert_eq(b.text, "Click")
	assert_eq(b.tooltip_text, "Tooltip text")
	b.free()

	var b2 = HFUIFactory.make_button("NoTip")
	assert_eq(b2.tooltip_text, "")
	b2.free()


func test_make_label_row_structure():
	var spin = HFUIFactory.make_spin(0, 10, 1, 5)
	var row = HFUIFactory.make_label_row("My Label", spin)
	assert_eq(row.get_child_count(), 2)
	assert_true(row.get_child(0) is Label)
	assert_eq((row.get_child(0) as Label).text, "My Label")
	assert_eq(row.get_child(1), spin)
	assert_eq(spin.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	row.free()


func test_make_label_row_min_width():
	var ctrl = HFUIFactory.make_spin(0, 1, 1, 0)
	var row = HFUIFactory.make_label_row("Wide", ctrl, 80)
	var lbl = row.get_child(0) as Label
	assert_eq(lbl.custom_minimum_size.x, 80)
	row.free()


func test_make_option_with_items():
	var opt = HFUIFactory.make_option(["A", "B", "C"])
	assert_eq(opt.item_count, 3)
	assert_eq(opt.get_item_text(0), "A")
	assert_eq(opt.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	opt.free()


func test_make_separator():
	var sep = HFUIFactory.make_separator()
	assert_true(sep is HSeparator)
	sep.free()


func test_make_spin_row_combines_label_and_spin():
	var row = HFUIFactory.make_spin_row("Size", 1.0, 10.0, 0.5, 5.0)
	assert_eq(row.get_child_count(), 2)
	var spin = row.get_child(1) as SpinBox
	assert_eq(spin.value, 5.0)
	assert_eq(spin.min_value, 1.0)
	row.free()
