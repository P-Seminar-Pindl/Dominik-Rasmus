extends Node
@export var height_modifier: int = 10
var selected_building: String = ""
var distribution_curve : Curve
var cell_size : Vector3
var chunk_render_distance : int = 32
var grid : GridMap
var anchor := Vector2.ZERO
# Tracks every placed building instance.
# Key: Vector3i (grid position)
# Value: Dictionary with building data and runtime state
var placed_buildings: Dictionary = {}


func place_building(grid_pos: Vector3i, building_id: String) -> void:
	var data = LibraryManager.buildings.get(building_id, {})
	if data.is_empty():
		push_error("Tried to place unknown building: " + building_id)
		return

	placed_buildings[grid_pos] = {
		"id":                 building_id,
		"grid_id":            data.get("id", -1),
		"costs":              data.get("costs", {}),
		"input":              data.get("input", {}),
		"output":             data.get("output", {}),
		"workforce_required": data.get("workforce_required", 0),
		"productivity":       1.0,
		"population":         0,
	}


func remove_building(grid_pos: Vector3i) -> void:
	placed_buildings.erase(grid_pos)


func get_building(grid_pos: Vector3i) -> Dictionary:
	return placed_buildings.get(grid_pos, {})
