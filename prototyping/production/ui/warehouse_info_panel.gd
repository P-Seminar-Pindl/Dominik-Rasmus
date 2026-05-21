extends DefaultInfoPanel

var _storage_label: Label


func _populate_extra(vbox: VBoxContainer) -> void:
	vbox.add_child(HSeparator.new())
	_add_section(vbox, "Storage:")
	_storage_label = Label.new()
	vbox.add_child(_storage_label)


func _show_extra(data: Dictionary) -> void:
	var res := data.get("resource", null) as StorageBuildingResource
	if res and _storage_label:
		_storage_label.text = _fmt(res.storage_slots)
