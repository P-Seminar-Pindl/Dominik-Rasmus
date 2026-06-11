extends DefaultInfoPanel

var _population_label: Label


func _populate_extra(vbox: VBoxContainer) -> void:
	vbox.add_child(HSeparator.new())
	_add_section(vbox, "Housing:")
	_population_label = Label.new()
	vbox.add_child(_population_label)


func _show_extra(data: Dictionary) -> void:
	var res := data.get("resource", null) as HouseBuildingResource
	if res and _population_label:
		_population_label.text = "  Capacity: %d" % res.population_capacity
