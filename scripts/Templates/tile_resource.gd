extends Resource
class_name TileResource

@export var name: String = ""
@export var mesh: BoxMesh = BoxMesh.new()
@export var collision_size: Vector3 = Vector3(2,2,2)
@export var size : Vector3 = Vector3(2,2,2)
@export var texture: Texture

func setup_mesh():
	var mat = StandardMaterial3D.new()
	if texture:
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 1.0
		
		
		# Größe setzen
	if mesh is BoxMesh:
		mesh.size = size
		
		# Material auf alle Surfaces
	for s in range(mesh.get_surface_count()):
		mesh.surface_set_material(s, mat)
