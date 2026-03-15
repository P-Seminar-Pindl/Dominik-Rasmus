extends PanelContainer

# A simple sidebar that lists buildings from LibraryManager and emits a signal when one is selected.
# To use:
# 1) Make sure LibraryManager.PopulateBuildings(grid) is called before this sidebar is shown.
# 2) Add this scene to your UI (e.g. as a child of your main Control node).
# 3) Connect to `building_selected` to know what was chosen.

signal building_selected(building_name: String, building_data: Dictionary)

@export var title: String = "Buildings"
@export var button_min_height: int = 40
@export var group_name: String = "building_sidebar"

# Public: currently selected building name (or "" when none)
var selected_building: String = ""
var _has_populated: bool = false

func _ready() -> void:
	# If buildings are populated later (e.g., in another node's _ready), we retry once.
	set_process(true)
	refresh()

func _process(_delta: float) -> void:
	if not _has_populated and LibraryManager.Buildings:
		refresh()

func refresh() -> void:
	# Safe guard - ensure LibraryManager has buildings populated.
	if not LibraryManager.Buildings:
		return
	_has_populated = true
	set_process(false)

	var list = $VBoxContainer/ScrollContainer/Items
	list.clear()

	# Title
	$VBoxContainer/Label.text = title

	for building_name in LibraryManager.Buildings.keys():
		var info = LibraryManager.Buildings[building_name]
		if typeof(info) != TYPE_DICTIONARY:
			continue

		var button = Button.new()
		button.text = building_name
		button.toggle_mode = true
		button.group = group_name
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(0, button_min_height)
		button.tooltip_text = _build_tooltip(info)
		button.connect("pressed", Callable(self, "_on_building_button_pressed"), [building_name])
		list.add_child(button)

func _build_tooltip(info: Dictionary) -> String:
	# Forms a small tooltip from available info keys.
	var parts := []
	for key in ["population", "income", "needs"]:
		if info.has(key):
			parts.append("%s: %s" % [key.capitalize(), info[key]])
	return parts.join("\n")

func _on_building_button_pressed(building_name: String) -> void:
	selected_building = building_name
	emit_signal("building_selected", building_name, LibraryManager.Buildings.get(building_name, {}))
