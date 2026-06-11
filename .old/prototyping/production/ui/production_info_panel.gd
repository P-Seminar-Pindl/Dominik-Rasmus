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

	# Local storage buffer + input buffer + carrier cargo
	var storage: Dictionary = data.get("storage", {})
	var input_buffer: Dictionary = data.get("input_buffer", {})
	var carrier_cargo: Dictionary = data.get("carrier_cargo", {})

	var storage_lines: PackedStringArray = []
	if not storage.is_empty():
		for item in storage.keys():
			var cap: int = _cap_for(res, item)
			storage_lines.append("  Out: %s: %d / %d" % [item, storage[item], cap])
	if not input_buffer.is_empty():
		for item in input_buffer.keys():
			storage_lines.append("  In: %s: %d" % [item, input_buffer[item]])
	if not carrier_cargo.is_empty():
		for item in carrier_cargo.keys():
			storage_lines.append("  Cargo: %s: %d" % [item, carrier_cargo[item]])

	if storage_lines.is_empty():
		_storage_label.text = "  (empty)"
	else:
		_storage_label.text = "\n".join(storage_lines)

	# Production state + carrier state + progress
	var dist: int           = data.get("warehouse_distance", -1)
	var prod_state: String  = data.get("prod_state", "idle")
	var carrier_state: String = data.get("carrier_state", "idle")
	var progress: float     = data.get("logistics_progress", 0.0)
	var timer: float        = data.get("timer", 0.0)

	var status_lines: PackedStringArray = []

	# Production status
	match prod_state:
		"idle":
			status_lines.append("  Prod: Idle")
		"producing":
			status_lines.append("  Prod: %.1fs / %.1fs" % [timer, res.production_time])

	# Carrier status
	if dist < 0:
		status_lines.append("  [No warehouse]")
	else:
		match carrier_state:
			"idle":
				status_lines.append("  Carrier: Idle")
			"fetching":
				status_lines.append("  Carrier: Fetching (%.1f / %d)" % [progress, dist])
			"delivering":
				status_lines.append("  Carrier: Delivering (%.1f / %d)" % [progress, dist])

	_progress_label.text = "\n".join(status_lines)


static func _cap_for(res: ProductionBuildingResource, item: String) -> int:
	for slot in res.storage_slots:
		if slot.item == item:
			return slot.amount
	return 0
