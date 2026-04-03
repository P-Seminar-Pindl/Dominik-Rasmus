extends Node
enum State{
	Collapsed,
	Expanded
}
static func AddSidebar(name: String, position, displayType: Dictionary,):
	var container = HBoxContainer.new()
	pass
static func ChangeSidebarState(Sidebar: ):
	
	pass
static func PopulateSidebar():
	pass
func _ready():
	var BuildMenu = AddSidebar("BuildMenu",10,LibraryManager.Buildings)
	BuildMenu
