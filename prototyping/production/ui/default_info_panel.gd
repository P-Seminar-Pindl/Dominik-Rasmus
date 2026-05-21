extends PanelContainer
class_name DefaultInfoPanel

var _title_label: Label
var _desc_label: Label
var _workforce_label: Label
var _costs_list: Label
var _upkeep_list: Label


func _ready() -> void:
	_build_ui()
	hide()


func _build_ui() -> void:
	custom_minimum_size = Vector2(260, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title row
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide)
	hbox.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_desc_label)

	vbox.add_child(HSeparator.new())

	_workforce_label = Label.new()
	vbox.add_child(_workforce_label)

	_add_section(vbox, "Costs:")
	_costs_list = Label.new()
	vbox.add_child(_costs_list)

	_add_section(vbox, "Upkeep:")
	_upkeep_list = Label.new()
	vbox.add_child(_upkeep_list)

	_populate_extra(vbox)


# Override in subclasses to append type-specific rows.
func _populate_extra(_vbox: VBoxContainer) -> void:
	pass


func _add_section(vbox: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(lbl)


# Called by camera_prototype to populate the panel.
func show_building(data: Dictionary) -> void:
	var res: BuildingResource = data.get("resource", null)
	if not res:
		return
	_title_label.text = res.info_title if res.info_title != "" else res.name
	_desc_label.text = res.info_description
	_workforce_label.text = "Workforce: %d" % res.workforce
	_costs_list.text = _fmt(res.costs)
	_upkeep_list.text = _fmt(res.upkeep)
	_show_extra(data)
	show()


# Override in subclasses to fill extra fields.
func _show_extra(_data: Dictionary) -> void:
	pass


static func _fmt(amounts: Array) -> String:
	if amounts.is_empty():
		return "  —"
	var lines: PackedStringArray = []
	for entry in amounts:
		lines.append("  %s × %d" % [entry.item, entry.amount])
	return "\n".join(lines)
