extends SceneTree

const OUTPUT_DIRECTORY := "/tmp/godot-pal-3d-assets"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	var packed := load(
		"res://game/presentation/action_combat_3d/tools/g3_asset_showcase.tscn"
	) as PackedScene
	if packed == null:
		push_error("G3 asset showcase could not load")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_DIRECTORY.path_join("g3_asset_showcase.png"))
	scene.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
