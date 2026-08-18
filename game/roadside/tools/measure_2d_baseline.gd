extends SceneTree

const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 180


func _initialize() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var packed := load("res://game/bootstrap/game_root.tscn") as PackedScene
	if packed == null:
		_finish_with_error("baseline could not load GameRoot")
		return
	var game_root := packed.instantiate() as GameRoot
	if game_root == null:
		_finish_with_error("baseline could not instantiate GameRoot")
		return
	get_root().add_child(game_root)
	await process_frame
	game_root.start_new_game()
	await process_frame
	await process_frame
	var map_scene := game_root.scene_stack.current_scene() as MapGameScene
	if map_scene == null:
		_finish_with_error("baseline did not enter a MapGameScene", game_root)
		return
	for _index: int in range(WARMUP_FRAMES):
		await process_frame
	var frame_times_ms: Array[float] = []
	var fps_total := 0.0
	var draw_calls_total := 0.0
	var primitives_total := 0.0
	for _index: int in range(SAMPLE_FRAMES):
		var started_at := Time.get_ticks_usec()
		await process_frame
		frame_times_ms.append(float(Time.get_ticks_usec() - started_at) / 1000.0)
		fps_total += Performance.get_monitor(Performance.TIME_FPS)
		draw_calls_total += Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		)
		primitives_total += Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		)
	frame_times_ms.sort()
	var average_frame_time := _average(frame_times_ms)
	var p95_index := mini(
		int(ceil(float(frame_times_ms.size()) * 0.95)) - 1,
		frame_times_ms.size() - 1
	)
	var report := {
		"command": "measure-2d-baseline",
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"map_id": String(map_scene.map_id),
		"viewport_size": {
			"width": get_root().size.x,
			"height": get_root().size.y,
		},
		"render_target_size": {
			"width": int(get_root().get_texture().get_size().x),
			"height": int(get_root().get_texture().get_size().y),
		},
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"average_fps": fps_total / float(SAMPLE_FRAMES),
		"average_frame_time_ms": average_frame_time,
		"p95_frame_time_ms": frame_times_ms[p95_index],
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_memory_peak_bytes": int(
			Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
		),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"average_draw_calls": draw_calls_total / float(SAMPLE_FRAMES),
		"average_primitives": primitives_total / float(SAMPLE_FRAMES),
		"video_adapter": RenderingServer.get_video_adapter_name(),
	}
	print(JSON.stringify(report))
	game_root.queue_free()
	await process_frame
	quit()


func _average(values: Array[float]) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size()) if not values.is_empty() else 0.0


func _finish_with_error(message: String, scene: Node = null) -> void:
	push_error(message)
	if scene != null:
		scene.queue_free()
	quit(1)
