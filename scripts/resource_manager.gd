# resource_manager.gd — autoload "ResourceManager"
# City-wide resource stockpile + worker pool.
extends Node

signal resources_changed
signal workers_changed

# Edit starting amounts here freely.
var stockpile: Dictionary = {
	"Gold":   150,
	"Wood":   30,
	"Planks": 40,
	"Stone":  20,
	"Food":   20,
}

# Worker pool — capacity comes from houses, usage from production buildings.
var worker_capacity: int = 0
var workers_used:    int = 0


func add(item: String, amount: int) -> void:
	stockpile[item] = stockpile.get(item, 0) + amount
	resources_changed.emit()


func remove(item: String, amount: int) -> bool:
	if not has_enough(item, amount):
		return false
	stockpile[item] -= amount
	resources_changed.emit()
	return true


func get_amount(item: String) -> int:
	return stockpile.get(item, 0)


func has_enough(item: String, amount: int) -> bool:
	return stockpile.get(item, 0) >= amount


func can_afford(costs: Array) -> bool:
	for cost in costs:
		if not has_enough(cost.item, cost.amount):
			return false
	return true


func pay(costs: Array) -> void:
	for cost in costs:
		remove(cost.item, cost.amount)


func refund(costs: Array, fraction: float = 0.5) -> void:
	for cost in costs:
		var back := int(floor(cost.amount * fraction))
		if back > 0:
			add(cost.item, back)


func set_workers(capacity: int, used: int) -> void:
	if capacity == worker_capacity and used == workers_used:
		return
	worker_capacity = capacity
	workers_used = used
	workers_changed.emit()
