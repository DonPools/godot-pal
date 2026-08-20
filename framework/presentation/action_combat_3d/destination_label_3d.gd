class_name DestinationLabel3D
extends Label3D

@export var plaque_size := Vector2(2.7, 0.72)


func _ready() -> void:
	fixed_size = false
	pixel_size = 0.012
	font_size = 48
	outline_size = 12
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	render_priority = 2
	modulate = Color(1.0, 0.82, 0.36, 1.0)
	_add_plaque()


func set_context_suppressed(suppressed: bool) -> void:
	visible = not suppressed


func _add_plaque() -> void:
	var border := _plaque_mesh(
		plaque_size, Color(0.72, 0.48, 0.16, 0.98), -2
	)
	border.name = &"PlaqueBorder"
	border.position = Vector3(0.0, 0.0, 0.04)
	add_child(border)
	var face := _plaque_mesh(
		plaque_size - Vector2(0.12, 0.12),
		Color(0.055, 0.038, 0.025, 0.97),
		-1
	)
	face.name = &"PlaqueFace"
	face.position = Vector3(0.0, 0.0, 0.035)
	add_child(face)


func _plaque_mesh(size: Vector2, color: Color, priority: int) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = priority
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	return instance
