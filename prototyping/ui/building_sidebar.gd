extends PanelContainer
class_name BuildingSidebar

signal item_selected(item_name: String)

var _buttons: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(180, 0)
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom",30)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 30)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Buildings"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Deselect / inspect mode button
	var none_btn := Button.new()
	none_btn.text = "None  (Inspect)"
	none_btn.toggle_mode = true
	none_btn.button_pressed = true
	none_btn.pressed.connect(func() -> void: _select(""))
	_buttons[""] = none_btn
	vbox.add_child(none_btn)

	vbox.add_child(HSeparator.new())

	# One button per registered building
	for building_name: String in LibraryManager.buildings:
		var btn := Button.new()
		btn.text = building_name
		btn.toggle_mode = true
		btn.pressed.connect(func() -> void: _select(building_name))
		_buttons[building_name] = btn
		vbox.add_child(btn)


# Depress all toggle buttons except the selected one, then update Global.
func _select(building_name: String) -> void:
	for key: String in _buttons:
		_buttons[key].button_pressed = (key == building_name)
	Global.selected_building = building_name
	item_selected.emit(building_name)
