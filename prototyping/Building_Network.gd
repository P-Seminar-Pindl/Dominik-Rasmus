# building_network.gd — autoload as BuildingNetwork
extends Node

var _grid: ProductionLine = null

func register(grid: ProductionLine) -> void:
	_grid = grid

func rebuild_network() -> void:
	if _grid == null:
		push_error("BuildingNetwork: grid not registered")
		return
	await _grid.rebuild_network()
