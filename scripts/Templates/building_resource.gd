extends Resource
class_name BuildingResource

const ResourceAmount = preload("res://scripts/Templates/resource_amount.gd")

@export_group("Identity")
@export var name: String = ""
@export var texture: Texture2D
@export var info_title: String = ""
@export var info_description: String = ""
@export var info_panel: PackedScene  # optional — if null, system picks default by type

@export_group("UI")
@export var show_in_sidebar: bool = true

@export_group("Variants")
@export var active_variant: String = ""  # name of the LibraryManager entry to swap to when connected

@export_group("Mesh")
@export var mesh: Mesh = BoxMesh.new()
@export var collision_size: Vector3 = Vector3(2, 2, 2)
@export var footprint_size: Vector2i = Vector2i(1, 1)  # cells on X, Z

@export_group("Economy")
@export var workforce: int = 0
@export var costs: Array[ResourceAmount] = []   # one-time build cost
@export var upkeep: Array[ResourceAmount] = []  # recurring cost per tick


func setup_mesh() -> void:
	if not texture or not mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.uv1_offset = Vector3(0.5, 0.5, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, mat)
