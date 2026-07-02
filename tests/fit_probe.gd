extends Node

const PM := preload("res://scripts/placement_manager.gd")


func _ready() -> void:
	var worst := 0.0
	var dir := DirAccess.open("res://data/buildings/")
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res := load("res://data/buildings/" + fname) as BuildingResource
			if res != null and res.scene != null:
				var inst: Node3D = res.scene.instantiate()
				PM._fit_to_footprint(inst, res.footprint_size)
				add_child(inst)
				var r := PM._merge_mesh_aabb(inst, inst.transform, AABB(), false)
				var aabb: AABB = r[0]
				var over_x: float = aabb.size.x - res.footprint_size.x
				var over_z: float = aabb.size.z - res.footprint_size.y
				var center := aabb.get_center()
				worst = maxf(worst, maxf(over_x, over_z))
				worst = maxf(worst, maxf(absf(center.x), absf(center.z)))
				worst = maxf(worst, absf(aabb.position.y))
				print("FIT %-16s fp=%s  fitted_xz=(%.2f, %.2f)  center_xz=(%.2f, %.2f)  y_min=%.3f" % [
					res.name, str(res.footprint_size),
					aabb.size.x, aabb.size.z,
					center.x, center.z, aabb.position.y,
				])
				inst.queue_free()
		fname = dir.get_next()
	print("FIT RESULT: " + ("OK" if worst < 0.01 else "worst deviation %.3f" % worst))
	get_tree().quit()
