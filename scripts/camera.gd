# camera_mesh.gd — standalone orbit camera for mesh prototype
# Orbit/pan/zoom logic copied from scripts/camera.gd, game-specific code removed.
extends Camera3D

@export var sensitivity_multi: float = 1.0

var anchor := Vector3.ZERO

var yaw   := 0.0
var pitch := 0.0
var distance      := 80.0
var target_distance := 80.0

const ZOOM_SPEED := 0.1
const ZOOM_MIN   := 2.0
const ZOOM_MAX   := 1000.0

var _dragging_orbit := false
var _dragging_pan   := false


func _ready() -> void:
	var offset := global_position - anchor
	distance        = offset.length()
	target_distance = distance
	yaw   = atan2(offset.x, offset.z)
	pitch = asin(offset.y / distance)


func _process(delta: float) -> void:
	distance = lerp(distance, target_distance, delta * 10.0)
	_update_camera()


func _update_camera() -> void:
	var x := distance * cos(pitch) * sin(yaw)
	var y := distance * sin(pitch)
	var z := distance * cos(pitch) * cos(yaw)
	global_position = anchor + Vector3(x, y, z)
	look_at(anchor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_orbit = event.pressed
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_pan = event.pressed
		elif event.pressed:
			var zoom_dir := 0
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_dir = -1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_dir = 1
			if zoom_dir != 0:
				target_distance = clamp(
					target_distance + target_distance * ZOOM_SPEED * zoom_dir,
					ZOOM_MIN, ZOOM_MAX
				)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging_orbit:
			var delta = event.relative
			yaw   -= delta.x * 0.005
			pitch += delta.y * 0.005
			pitch  = clamp(pitch, deg_to_rad(3), deg_to_rad(89))
			get_viewport().set_input_as_handled()

		elif _dragging_pan:
			var delta = event.relative
			var right   := global_transform.basis.x
			var forward := -global_transform.basis.z
			right.y   = 0.0
			forward.y = 0.0
			right   = right.normalized()
			forward = forward.normalized()
			var sensitivity := global_position.distance_to(anchor) * sensitivity_multi / 1000.0
			var move: Vector3 = (right * -delta.x + forward * delta.y) * sensitivity
			global_position += move
			anchor          += move
			get_viewport().set_input_as_handled()


func anchor_2d() -> Vector2:
	return Vector2(anchor.x, anchor.z)
