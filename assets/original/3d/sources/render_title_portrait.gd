extends SceneTree

const OUTPUT_PATH := "res://assets/original/3d/title_traveler_portrait.png"
const MODEL := preload("res://assets/original/3d/models/humanoid_base.glb")


func _initialize() -> void:
	call_deferred("_render")


func _render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(156, 98)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var model := MODEL.instantiate() as Node3D
	model.rotation.y = deg_to_rad(-28.0)
	world.add_child(model)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.58)
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -36.0, 0.0)
	light.light_color = Color(1.0, 0.88, 0.68)
	light.light_energy = 1.0
	world.add_child(light)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	world.add_child(camera)
	camera.position = Vector3(3.2, 2.45, 3.2)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	camera.current = true

	for _frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.get_size() != viewport.size:
		push_error("failed to render the 3D title portrait")
		quit(1)
		return
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if error != OK:
		push_error("failed to save title portrait: %s" % error_string(error))
		quit(1)
		return
	print("rendered %s" % OUTPUT_PATH)
	quit(0)
