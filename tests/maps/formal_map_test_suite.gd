class_name FormalMapTestSuite
extends RefCounted

var _scene_tree: SceneTree
var _failures: PackedStringArray = []


func run(scene_tree: SceneTree) -> PackedStringArray:
	_scene_tree = scene_tree
	await _test_roadside_shop_3d_scene()
	await _test_herb_slope_3d_scene()
	await _test_north_slope_wilds_3d_scene()
	await _test_3d_gathering_flow()
	return _failures


func _test_roadside_shop_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/roadside_shop_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D roadside shop should instantiate as MapGameScene3D")
	if scene == null:
		return
	_scene_tree.root.add_child(scene)
	await _scene_tree.process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	var shopkeeper := scene.get_node_or_null(^"WorldRoot/Shopkeeper") as NpcCharacter3D
	var interactable := scene.get_node_or_null(
		^"WorldRoot/Shopkeeper/Interactable"
	) as StoryInteractable3D
	var wilds_portal := scene.get_node_or_null(
		^"WorldRoot/TrailToWilds/Interactable"
	) as StoryInteractable3D
	var herb_portal := scene.get_node_or_null(
		^"WorldRoot/TrailToHerbSlope/Interactable"
	) as StoryInteractable3D
	var wilds_label := scene.get_node_or_null(
		^"WorldRoot/TrailToWilds/DestinationLabel"
	) as Label3D
	var herb_label := scene.get_node_or_null(
		^"WorldRoot/TrailToHerbSlope/DestinationLabel"
	) as Label3D
	var fade_obstacle := scene.get_node_or_null(^"WorldRoot/PineTree") as Node3D
	var shopkeeper_animation: AnimationPlayer
	if shopkeeper != null:
		var npc_animation_players := shopkeeper.find_children(
			"*", "AnimationPlayer", true, false
		)
		if not npc_animation_players.is_empty():
			shopkeeper_animation = npc_animation_players[0] as AnimationPlayer
	var fade_meshes: Array[MeshInstance3D] = []
	if fade_obstacle != null:
		for candidate: Node in fade_obstacle.find_children(
			"*", "MeshInstance3D", true, false
		):
			if candidate is MeshInstance3D:
				fade_meshes.append(candidate as MeshInstance3D)
	_expect(
		ground != null
		and ground.get_used_cells().size() == 252
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() > 0,
		"3D roadside shop should bake its 18x14 ground and usable navigation"
	)
	_expect(
		fade_obstacle != null
		and fade_obstacle.is_in_group(&"camera_fade_obstacle")
		and not fade_meshes.is_empty(),
		"camera-blocking trees should expose fadeable runtime meshes"
	)
	if fade_obstacle != null and not fade_meshes.is_empty():
		scene.camera_3d.apply_obstacle_fade({fade_obstacle: true})
		_expect(
			is_equal_approx(fade_meshes[0].transparency, 0.62),
			"camera occlusion should fade a blocking environment model"
		)
		scene.camera_3d.restore_obstacles()
		_expect(
			is_zero_approx(fade_meshes[0].transparency),
			"camera occlusion should restore transparency after the obstacle clears"
		)
	_expect(
		shopkeeper != null
		and shopkeeper.definition != null
		and shopkeeper.definition.id == &"npc.roadside.shopkeeper"
		and shopkeeper_animation != null
		and String(shopkeeper_animation.current_animation).get_file() == "idle"
		and interactable != null
		and interactable.binding != null
		and interactable.binding.trigger_id == &"talk_shopkeeper"
		and interactable.actor_definition_id == &"npc.roadside.shopkeeper",
		"3D shopkeeper definition, gathering trigger, and story origin actor ID should agree"
	)
	_expect(
		wilds_portal != null
		and wilds_portal.portal_target_map_id == &"map.roadside.north_slope_wilds"
		and wilds_portal.portal_target_spawn_id == &"from_shop"
		and herb_portal != null
		and herb_portal.portal_target_map_id == &"map.roadside.herb_slope"
		and herb_portal.portal_target_spawn_id == &"safe_entry"
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_wilds") is Marker3D
		and wilds_label != null
		and wilds_label.text == "往原野"
		and herb_label != null
		and herb_label.text == "往药草地",
		"3D shop should expose paired semantic portals to the wilds and herb slope"
	)
	if wilds_label is DestinationLabel3D:
		(wilds_label as DestinationLabel3D).set_context_suppressed(true)
		_expect(
			not wilds_label.visible,
			"a nearby interaction prompt should hide competing world plaques"
		)
		(wilds_label as DestinationLabel3D).set_context_suppressed(false)
		_expect(
			wilds_label.visible,
			"world plaques should return after the interaction prompt clears"
		)
	var from_wilds := scene.get_node(^"WorldRoot/SpawnPoints/from_wilds") as Marker3D
	var from_slope := scene.get_node(^"WorldRoot/SpawnPoints/from_slope") as Marker3D
	_expect(
		from_wilds.global_position.distance_to(wilds_portal.global_position) > 2.2
		and from_wilds.global_position.distance_to(wilds_portal.global_position) < 6.0
		and from_slope.global_position.distance_to(herb_portal.global_position) > 2.2
		and from_slope.global_position.distance_to(herb_portal.global_position) < 6.0,
		"shop exits should be visible from paired spawns without immediately retriggering"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "da4f7f6d8fd0fe5a7bfa6587e6a84d472522a457081ddbeb87b419432cf03915",
		"3D roadside shop should retain its reviewed generator v3 plan hash"
	)
	var pine := scene.get_node(^"WorldRoot/PineTree") as StaticBody3D
	scene.player_3d.position = pine.position + Vector3(0.0, 0.0, 2.0)
	var collision := scene.player_3d.move_and_collide(Vector3(0.0, 0.0, -2.0))
	_expect(
		collision != null and collision.get_collider() == pine,
		"3D shop environment should physically stop player movement"
	)
	scene.queue_free()
	await _scene_tree.process_frame


func _test_herb_slope_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/herb_slope_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D herb slope should instantiate as MapGameScene3D")
	if scene == null:
		return
	_scene_tree.root.add_child(scene)
	await _scene_tree.process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var detail := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedDetailGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	_expect(
		ground != null
		and ground.get_used_cells().size() == 512
		and detail != null
		and detail.get_used_cells().size() > 0
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() > 0,
		"3D herb slope should bake 32x16 terrain, habitat detail, and navigation"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "b430c6ce06cd716e64c9b97ff8a6e8d1ea1861ffedda14770cda8977b3e43fdd",
		"3D herb slope should retain its reviewed generator v3 plan hash"
	)
	var patch := scene.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	var run := GameRun.new()
	patch.configure_world_state(run, &"map.roadside.herb_slope")
	_expect(
		patch.full_visual.visible
		and not patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_INHERIT,
		"fresh 3D herb should show a complete available plant"
	)
	run.flags.set_value(RoadsideGatheringStory.FIRST_WEST)
	patch.refresh_world_state()
	_expect(
		not patch.full_visual.visible
		and patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_DISABLED,
		"leave-root harvest should show a cut unavailable 3D plant for the current trip"
	)
	run.flags.set_value(RoadsideGatheringStory.SECOND_TRIP_STARTED)
	patch.refresh_world_state()
	_expect(
		patch.full_visual.visible
		and not patch.cut_visual.visible
		and patch.interactable.process_mode == Node.PROCESS_MODE_INHERIT,
		"leave-root 3D herb should regrow when the second trip starts"
	)
	run.flags.set_value(RoadsideGatheringStory.UPROOTED_WEST)
	patch.refresh_world_state()
	_expect(
		not patch.visible and patch.process_mode == Node.PROCESS_MODE_DISABLED,
		"uprooted 3D herb should remain absent"
	)
	var portal := scene.get_node(
		^"WorldRoot/TrailBack/Interactable"
	) as StoryInteractable3D
	_expect(
		portal.portal_target_map_id == &"map.roadside.shop"
		and portal.portal_target_spawn_id == &"from_slope"
		and scene.entry_bindings.size() == 1
		and scene.entry_bindings[0].event is RoadsideGatheringStory
		and scene.entry_bindings[0].trigger_id == &"enter_herb_slope",
		"3D herb slope should preserve its semantic return portal and entry trigger"
	)
	scene.queue_free()
	await _scene_tree.process_frame


func _test_north_slope_wilds_3d_scene() -> void:
	var path := "res://game/roadside/action_combat_3d/maps/north_slope_wilds_3d.tscn"
	var packed := load(path) as PackedScene
	var scene := packed.instantiate() as MapGameScene3D if packed != null else null
	_expect(scene != null, "3D north slope wilds should instantiate as MapGameScene3D")
	if scene == null:
		return
	_scene_tree.root.add_child(scene)
	await _scene_tree.process_frame
	var ground := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedGroundGrid"
	) as GridMap
	var detail := scene.get_node_or_null(
		^"WorldRoot/Terrain/GeneratedDetailGrid"
	) as GridMap
	var navigation := scene.get_node_or_null(
		^"WorldRoot/NavigationRegion3D"
	) as NavigationRegion3D
	var generated_prop_count := 0
	for child: Node in scene.get_node(^"WorldRoot/Terrain").get_children():
		if String(child.get_meta(&"map_generation_key", "")).begins_with("generated.prop."):
			generated_prop_count += 1
	_expect(
		ground != null
		and ground.get_used_cells().size() == 2048
		and detail != null
		and detail.get_used_cells().size() >= 80
		and generated_prop_count == 92
		and navigation != null
		and navigation.navigation_mesh.get_polygon_count() == 1923,
		"3D wilds should keep its 64x32 ecological and navigation budgets"
	)
	_expect(
		String(scene.get_meta(&"map_generation_plan_hash", ""))
		== "0c84f5e1050250c8b225c441ed59431cb3843f0d1e857bf867b94c4bb3ca6939",
		"3D wilds should retain its reviewed generator v3 plan hash"
	)
	var shop_portal := scene.get_node(
		^"WorldRoot/TrailToShop/Interactable"
	) as StoryInteractable3D
	var pack_portal := scene.get_node(
		^"WorldRoot/BeastTrailMarker/Interactable"
	) as StoryInteractable3D
	_expect(
		shop_portal.portal_target_map_id == &"map.roadside.shop"
		and shop_portal.portal_target_spawn_id == &"from_wilds"
		and pack_portal.portal_target_map_id == &"map.roadside.north_slope_pack"
		and pack_portal.portal_target_spawn_id == &"safe_entry"
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_shop") is Marker3D
		and scene.get_node_or_null(^"WorldRoot/SpawnPoints/from_pack") is Marker3D,
		"3D wilds should preserve both human-authored semantic portals"
	)
	_expect(
		scene.get_node_or_null(^"WorldRoot/GeneratedMapBoundary3D") is StaticBody3D
		and scene.camera_3d.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"3D wilds should use generated bounds and the fixed orthographic camera"
	)
	scene.queue_free()
	await _scene_tree.process_frame


func _test_3d_gathering_flow() -> void:
	var packed := load("res://game/bootstrap/game_root.tscn") as PackedScene
	var game_root := packed.instantiate() as GameRoot
	_scene_tree.root.add_child(game_root)
	await _scene_tree.process_frame
	game_root.start_new_game()
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	var starting_money := game_root.game_run.economy.money
	var wilds_map := game_root.content_database.map(&"map.roadside.north_slope_wilds")
	var gathering_story := wilds_map.story_module as RoadsideGatheringStory
	game_root.travel_to(wilds_map, wilds_map.default_spawn_id)
	await _scene_tree.process_frame
	await _scene_tree.process_frame
	var wilds := game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(wilds, ^"WorldRoot/TrailToShop/Interactable")
	await _drive_story_ui(game_root, [])
	var shop := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		shop != null
		and shop.map_id == &"map.roadside.shop"
		and game_root.game_run.location.spawn_id == &"from_wilds",
		"3D wilds portal should enter the shop through stable map and spawn IDs"
	)
	_interact_3d(shop, ^"WorldRoot/TrailToWilds/Interactable")
	await _drive_story_ui(game_root, [])
	wilds = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		wilds != null
		and wilds.map_id == &"map.roadside.north_slope_wilds"
		and game_root.game_run.location.spawn_id == &"from_shop",
		"shop should return to the paired wilds boundary spawn"
	)
	_interact_3d(wilds, ^"WorldRoot/BeastTrailMarker/Interactable")
	await _drive_story_ui(game_root, [])
	var pack := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		pack != null
		and pack.map_id == &"map.roadside.north_slope_pack"
		and game_root.game_run.location.spawn_id == &"safe_entry",
		"wilds should enter the combat trail through its safe boundary spawn"
	)
	_interact_3d(pack, ^"WorldRoot/ReturnMarker/Interactable")
	await _drive_story_ui(game_root, [])
	wilds = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		wilds != null
		and wilds.map_id == &"map.roadside.north_slope_wilds"
		and game_root.game_run.location.spawn_id == &"from_pack",
		"combat trail should return to the paired wilds boundary spawn"
	)
	_interact_3d(wilds, ^"WorldRoot/TrailToShop/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/TrailToHerbSlope/Interactable")
	await _drive_story_ui(game_root, [])
	var herb_slope := game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		herb_slope != null
		and herb_slope.map_id == &"map.roadside.herb_slope"
		and game_root.game_run.location.spawn_id == &"safe_entry",
		"shop should expose a physical path to the herb slope before the commission"
	)
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		shop != null
		and shop.map_id == &"map.roadside.shop"
		and game_root.game_run.location.spawn_id == &"from_slope",
		"herb slope should return to the paired shop boundary spawn"
	)
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [&"accept", &"safe_route"])
	herb_slope = game_root.scene_stack.current_scene() as MapGameScene3D
	_expect(
		herb_slope != null
		and herb_slope.map_id == &"map.roadside.herb_slope"
		and game_root.game_run.story.get_stage(
			gathering_story.id,
			gathering_story.initial_stage
		) == &"trip_one_midday",
		"first 3D gathering route should arrive through the safe semantic spawn"
	)
	await _drive_story_ui(game_root, [])
	_interact_3d(herb_slope, ^"WorldRoot/HerbWest/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	var west_patch := herb_slope.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	_expect(
		west_patch.cut_visual.visible and not west_patch.full_visual.visible,
		"the first leave-root choice should immediately update the 3D plant"
	)
	_interact_3d(herb_slope, ^"WorldRoot/HerbCentre/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [])
	_expect(
		game_root.game_run.story.get_stage(
			gathering_story.id,
			gathering_story.initial_stage
		) == &"between_trips"
		and game_root.game_run.economy.money == starting_money + 6,
		"first late 3D delivery should atomically pay six coins and open the second trip"
	)
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [&"accept", &"safe_route"])
	herb_slope = game_root.scene_stack.current_scene() as MapGameScene3D
	await _drive_story_ui(game_root, [])
	west_patch = herb_slope.get_node(^"WorldRoot/HerbWest") as HarvestPatch3D
	_expect(
		west_patch.full_visual.visible and west_patch.interactable.is_available(),
		"the second 3D trip should restore a leave-root plant"
	)
	_interact_3d(herb_slope, ^"WorldRoot/HerbWest/Interactable")
	await _drive_story_ui(game_root, [&"leave_root"])
	_interact_3d(herb_slope, ^"WorldRoot/HerbCentre/Interactable")
	await _drive_story_ui(game_root, [&"uproot"])
	var centre_patch := herb_slope.get_node(^"WorldRoot/HerbCentre") as HarvestPatch3D
	_expect(
		not centre_patch.visible
		and game_root.game_run.world.is_completed(
			&"map.roadside.herb_slope",
			&"herb.centre"
		),
		"uprooting should hide and persist only the selected 3D source"
	)
	_interact_3d(herb_slope, ^"WorldRoot/TrailBack/Interactable")
	await _drive_story_ui(game_root, [])
	shop = game_root.scene_stack.current_scene() as MapGameScene3D
	_interact_3d(shop, ^"WorldRoot/Shopkeeper/Interactable")
	await _drive_story_ui(game_root, [])
	var herb := game_root.content_database.item(&"item.roadside.fanqing_grass")
	_expect(
		game_root.game_run.story.get_stage(
			gathering_story.id,
			gathering_story.initial_stage
		) == &"completed"
		and game_root.game_run.inventory.quantity(herb.id) == 1
		and game_root.game_run.economy.money == starting_money + 12,
		"the complete two-trip 3D flow should preserve the uproot surplus and settle money and story state"
	)
	game_root.queue_free()
	await _scene_tree.process_frame


func _interact_3d(scene: MapGameScene3D, path: NodePath) -> void:
	if scene == null:
		_expect(false, "3D interaction requires an active map")
		return
	var interactable := scene.get_node_or_null(path) as StoryInteractable3D
	if interactable == null:
		_expect(false, "3D interaction target should exist: %s" % path)
		return
	scene.player_3d.global_position = interactable.global_position + Vector3(1.2, 0.0, 0.0)
	scene._on_player_interact_3d()


func _drive_story_ui(game_root: GameRoot, requested_choices: Array[StringName]) -> void:
	var choices: Array[StringName] = requested_choices.duplicate()
	var idle_frames := 0
	for _frame: int in range(1200):
		if game_root.story_director.is_busy() or game_root.dialogue_layer.is_active():
			idle_frames = 0
			if game_root.dialogue_layer.is_waiting_for_option():
				if choices.is_empty():
					_expect(false, "3D story flow opened an unexpected dialogue option")
					game_root.dialogue_layer.option_selected.emit(&"later")
				else:
					game_root.dialogue_layer.option_selected.emit(choices.pop_front())
			elif game_root.dialogue_layer.is_active():
				game_root.dialogue_layer.advance_requested.emit()
		else:
			idle_frames += 1
			if idle_frames >= 3:
				_expect(choices.is_empty(), "3D story flow did not consume all requested choices")
				return
		await _scene_tree.process_frame
	_expect(false, "3D story flow timed out")




func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
