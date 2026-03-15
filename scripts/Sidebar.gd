extends Node
class_name SideBar

var Tiles = LibraryManager.Tiles  

enum state {}

static func AddSideBar(name: String, type: Dictionary , position: Vector2 ):
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(200, 400)
	var VBox = VBoxContainer.new()
	panel.add_child(VBox)
	PopulateSidebar("test", type, VBox)
	return panel
	
	
static func PopulateSidebar(name: String, type: Dictionary, parent):
	for x in type: 
		var button = Button.new()
		button.text = "test"
		parent.add_child(button)
	
	pass
