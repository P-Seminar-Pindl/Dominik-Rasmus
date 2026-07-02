# hud.gd — CanvasLayer in Game.tscn
# Top resource bar, settlement tier label, and a click-to-inspect building
# info panel. All UI is built in code.
extends CanvasLayer

# Always shown; other goods (Anno-style chain products) appear once owned.
const RESOURCES := ["Gold", "Wood", "Planks", "Stone", "Bricks", "Food"]
const NO_TILE := Vector2i(-99999, -99999)

var _labels: Dictionary = {}  # item → Label
var _res_box: HBoxContainer
var _worker_label: Label
var _tier_label:   Label

var _panel:          PanelContainer
var _panel_title:    Label
var _panel_desc:     Label
var _panel_info:     Label
var _panel_status:   Label
var _panel_progress: ProgressBar
var _selected_anchor: Vector2i = NO_TILE

@onready var _placement: Node3D = get_node("../PlacementManager")


func _ready() -> void:
	_build_top_bar()
	_build_tier_label()
	_build_info_panel()

	ResourceManager.resources_changed.connect(_refresh_resources)
	ResourceManager.workers_changed.connect(_refresh_workers)
	_placement.building_clicked.connect(_on_building_clicked)
	_placement.building_placed.connect(_on_building_placed)
	_placement.building_removed.connect(_on_building_removed)

	_refresh_resources()
	_refresh_workers()
	_refresh_tier()


func _process(_delta: float) -> void:
	if _panel.visible:
		_refresh_panel()


# ── UI construction ───────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 6.0
	_res_box = HBoxContainer.new()
	_res_box.add_theme_constant_override("separation", 20)
	panel.add_child(_res_box)
	for key in RESOURCES:
		var label := Label.new()
		_res_box.add_child(label)
		_labels[key] = label
	_worker_label = Label.new()
	_res_box.add_child(_worker_label)
	add_child(panel)


func _build_tier_label() -> void:
	_tier_label = Label.new()
	_tier_label.position = Vector2(12, 40)
	_tier_label.add_theme_font_size_override("font_size", 22)
	add_child(_tier_label)


func _build_info_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -12.0
	_panel.offset_bottom = -12.0
	_panel.custom_minimum_size = Vector2(260, 0)
	_panel.visible = false

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_panel_title)

	_panel_desc = Label.new()
	_panel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_panel_desc)

	_panel_info = Label.new()
	box.add_child(_panel_info)

	_panel_status = Label.new()
	box.add_child(_panel_status)

	_panel_progress = ProgressBar.new()
	_panel_progress.show_percentage = false
	_panel_progress.custom_minimum_size = Vector2(0, 10)
	box.add_child(_panel_progress)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var demolish := Button.new()
	demolish.text = "Demolish (50% refund)"
	demolish.pressed.connect(_on_demolish_pressed)
	buttons.add_child(demolish)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: _panel.visible = false)
	buttons.add_child(close)

	add_child(_panel)


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_resources() -> void:
	# Chain goods get a label the first time they show up in the stockpile.
	var extras: Array = []
	for key in ResourceManager.stockpile:
		if not key in RESOURCES:
			extras.append(key)
	extras.sort()
	for key in extras:
		if not _labels.has(key):
			var label := Label.new()
			_res_box.add_child(label)
			_res_box.move_child(_worker_label, -1)
			_labels[key] = label

	for key in _labels:
		var amount: int = ResourceManager.get_amount(key)
		_labels[key].text = "%s: %d" % [key, amount]
		_labels[key].modulate = Color(1.0, 0.4, 0.4) if amount == 0 else Color.WHITE
		_labels[key].visible = key in RESOURCES or amount > 0


func _refresh_workers() -> void:
	_worker_label.text = "Workers: %d/%d" % [ResourceManager.workers_used, ResourceManager.worker_capacity]
	_worker_label.modulate = Color(1.0, 0.4, 0.4) \
			if ResourceManager.workers_used >= ResourceManager.worker_capacity else Color.WHITE


func _refresh_tier() -> void:
	var houses := 0
	for anchor in _placement.placed_buildings:
		if _placement.placed_buildings[anchor].get("resource", null) is HouseBuildingResource:
			houses += 1
	var tier := "Outpost"
	if houses >= 15:
		tier = "City"
	elif houses >= 8:
		tier = "Town"
	elif houses >= 3:
		tier = "Village"
	_tier_label.text = "%s (%d houses)" % [tier, houses]


func _refresh_panel() -> void:
	var pb: Dictionary = _placement.placed_buildings
	if not pb.has(_selected_anchor):
		_panel.visible = false
		return
	var data: Dictionary = pb[_selected_anchor]
	var res: BuildingResource = data["resource"]

	_panel_title.text = res.info_title if res.info_title != "" else res.name
	_panel_desc.text = res.info_description

	if res is ProductionBuildingResource:
		var prod := res as ProductionBuildingResource
		_panel_info.text = "%s → %s every %.0fs   Workers: %d/%d" % [
			_amounts_text(prod.input) if not prod.input.is_empty() else "—",
			_amounts_text(prod.output),
			prod.production_time,
			data.get("workers_assigned", 0), prod.workforce,
		]
		_panel_status.text = "Status: " + str(data.get("status", "Idle"))
		_panel_progress.visible = data.get("prod_state", "idle") == "producing"
		_panel_progress.max_value = prod.production_time
		_panel_progress.value = data.get("timer", 0.0)
	elif res is HouseBuildingResource:
		_panel_info.text = "Houses %d workers" % (res as HouseBuildingResource).population_capacity
		_panel_status.text = ""
		_panel_progress.visible = false
	elif res is StorageBuildingResource:
		_panel_info.text = "Collects goods from street-connected buildings"
		_panel_status.text = ""
		_panel_progress.visible = false
	else:
		var dist: int = data.get("warehouse_distance", -1)
		_panel_info.text = ""
		_panel_status.text = "Connected to warehouse" if dist >= 0 else ""
		_panel_progress.visible = false


func _amounts_text(amounts: Array) -> String:
	var parts := PackedStringArray()
	for slot in amounts:
		parts.append("%s ×%d" % [slot.item, slot.amount])
	return ", ".join(parts)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_building_clicked(anchor: Vector2i) -> void:
	_selected_anchor = anchor
	_panel.visible = true
	_refresh_panel()


func _on_building_placed(_anchor: Vector2i, _res: BuildingResource) -> void:
	_refresh_tier()


func _on_building_removed(anchor: Vector2i) -> void:
	_refresh_tier()
	if anchor == _selected_anchor:
		_panel.visible = false
		_selected_anchor = NO_TILE


func _on_demolish_pressed() -> void:
	if _selected_anchor != NO_TILE:
		_placement.remove_building(_selected_anchor)
