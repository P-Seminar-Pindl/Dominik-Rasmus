extends DefaultInfoPanel

var _recipe_label: Label
var _storage_label: Label
var _progress_label: Label


func _populate_extra(vbox: VBoxContainer) -> void:
	vbox.add_child(HSeparator.new())
	_add_section(vbox, "Production:")
	_recipe_label = Label.new()
	vbox.add_child(_recipe_label)

	vbox.add_child(HSeparator.new())
	_add_section(vbox, "Local storage:")
	_storage_label = Label.new()
	vbox.add_child(_storage_label)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_progress_label)


func _show_extra(data: Dictionary) -> void:
	var res := data.get("resource", null) as ProductionBuildingResource
	if not res:
		return

	# Recipe line: "Logs × 1 → Planks × 1"  (or "→ Planks × 1" when no input)
	var input_str := _fmt(res.input)
	var output_str := _fmt(res.output)
	if res.input.is_empty():
		_recipe_label.text = "→ " + output_str.strip_edges()
	else:
		_recipe_label.text = input_str.strip_edges() + " → " + output_str.strip_edges()

	# Local storage buffer
	var storage: Dictionary = data.get("storage", {})
	if storage.is_empty():
		_storage_label.text = "  (empty)"
	else:
		var lines: PackedStringArray = []
		for item in storage.keys():
			var cap: int = _cap_for(res, item)
			lines.append("  %s: %d / %d" % [item, storage[item], cap])
		_storage_label.text = "\n".join(lines)

	# State + progress
	var dist: int            = data.get("warehouse_distance", -1)
	var prod_state: String   = data.get("prod_state", "idle")
	var log_state: String    = data.get("logistics_state", "idle")
	var progress: float      = data.get("logistics_progress", 0.0)
	var timer: float         = data.get("prod_timer", 0.0)

	var status_lines: PackedStringArray = []
	if dist < 0:
		status_lines.append("  [No warehouse connection]")
	match prod_state:
		"producing":
			status_lines.append("  Producing: %.1fs / %.1fs" % [timer, res.production_time])
		_:
			status_lines.append("  Production: idle")
	match log_state:
		"fetching":
			status_lines.append("  Fetching: %.1f / %d hops" % [progress, dist])
		"delivering":
			status_lines.append("  Delivering: %.1f / %d hops" % [progress, dist])
		_:
			status_lines.append("  Logistics: idle (dist: %d)" % dist)
	_progress_label.text = "\n".join(status_lines)


static func _cap_for(res: ProductionBuildingResource, item: String) -> int:
	for slot in res.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0
