extends Node
class_name SideBar

var Tiles = LibraryManager.Tiles  


enum state {}
func _ready() -> void:
	print(Tiles[1], "zrd")
	
	var Bar = AddSideBar("test", Tiles, Vector2(0,0))
	get_tree().root.add_child(PanelContainer.new())
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
		button.text = x
		parent.add_child(button)
	
	pass
