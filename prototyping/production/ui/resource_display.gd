extends PanelContainer

var _rows: VBoxContainer


func _ready() -> void:
	_build_ui()
	ResourceManager.resources_changed.connect(_refresh)
	_refresh()


func _build_ui() -> void:
	custom_minimum_size = Vector2(160, 0)
	# Anchor right edge to viewport right, grow leftward so the panel stays on-screen.
	anchor_left   = 1.0
	anchor_right  = 1.0
	anchor_top    = 0.0
	anchor_bottom = 0.0
	offset_right  = -8.0   # 8 px gap from the right edge
	offset_top    = 8.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Resources"
	title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	vbox.add_child(_rows)


func _refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()

	for item in ResourceManager.stockpile.keys():
		var lbl := Label.new()
		lbl.text = "%s: %d" % [item, ResourceManager.stockpile[item]]
		_rows.add_child(lbl)
