extends Panel
class_name Sidebar

signal item_selected(item_name: String)

var vbox = VBoxContainer.new()


func populate(items: Dictionary) -> void:
	add_child(vbox)
	for key in items:
		var button = Button.new()
		button.text = str(key)
		button.pressed.connect(func() -> void: item_selected.emit(key))
		vbox.add_child(button)
