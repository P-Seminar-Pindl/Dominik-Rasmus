extends Node3D

const SKY_TEXTURE_PATH := "res://textures/kloofendal_48d_partly_cloudy_puresky.jpg"

@onready var _world: Node3D = $World
@onready var _light: DirectionalLight3D = $DirectionalLight3D


func _ready() -> void:
	_configure_light()
	_configure_environment()
	_tune_terrain_shape()


func _configure_light() -> void:
	_light.shadow_enabled = true
	_light.shadow_bias = 0.015
	_light.shadow_normal_bias = 0.8
	_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_light.directional_shadow_blend_splits = true
	_light.directional_shadow_max_distance = 360.0
	_light.directional_shadow_split_1 = 0.14
	_light.directional_shadow_split_2 = 0.32
	_light.directional_shadow_split_3 = 0.62
	_light.directional_shadow_pancake_size = 12.0


func _configure_environment() -> void:
	var sky_texture := load(SKY_TEXTURE_PATH) as Texture2D
	if sky_texture == null:
		return

	var panorama_material := PanoramaSkyMaterial.new()
	panorama_material.panorama = sky_texture

	var sky := Sky.new()
	sky.sky_material = panorama_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.ambient_light_sky_contribution = 1.0
	get_viewport().world_3d.environment = environment


func _tune_terrain_shape() -> void:
	if _world == null or not _world.has_method("get"):
		return

	var cfg = _world.get("cfg")
	if cfg == null:
		return

	if cfg.get("height_modifier") != null:
		cfg.height_modifier = 34
