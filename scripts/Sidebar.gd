extends Panel
class_name SideBar
signal item_selected(item_name: String)
@onready var panel = self
var Tiles = LibraryManager.Tiles  
var vbox = VBoxContainer.new()

func populate(items: Dictionary):
	panel.add_child(vbox)
	for key in items:
		var button=Button.new()
		button.text = str(key)
		button.pressed.connect(func(): item_selected.emit(key))
		vbox.add_child(button)
enum state {}
