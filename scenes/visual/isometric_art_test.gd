class_name IsometricArtTest
extends Node2D

@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var y_sort_root: Node2D = $YSortRoot
@onready var player: PlayerCharacter = $YSortRoot/PlayerCharacter
@onready var shopkeeper: NpcCharacter = $YSortRoot/Shopkeeper
@onready var pine_tree: StaticBody2D = $YSortRoot/PineTree
@onready var feedback_label: Label = $HudLayer/FeedbackPanel/Feedback


func _ready() -> void:
	_ensure_input_actions()
	var actor := load("res://content/actors/li_xiaoyao.tres") as ActorDefinition
	player.configure(actor)
	shopkeeper.configure()
	player.interact_requested.connect(_on_player_interact)
	var player_camera := player.get_node_or_null(^"CameraRig") as Camera2D
	if player_camera != null:
		player_camera.enabled = false


func _on_player_interact() -> void:
	if player.global_position.distance_to(shopkeeper.global_position) <= 42.0:
		feedback_label.text = "店主：山路刚干，先看看鞋底。"
	else:
		feedback_label.text = "附近没人应声。"


func _ensure_input_actions() -> void:
	_copy_action(&"move_north", &"ui_up")
	_copy_action(&"move_south", &"ui_down")
	_copy_action(&"move_west", &"ui_left")
	_copy_action(&"move_east", &"ui_right")
	_copy_action(&"interact", &"ui_accept")


func _copy_action(target: StringName, source: StringName) -> void:
	if not InputMap.has_action(target):
		InputMap.add_action(target)
	for event: InputEvent in InputMap.action_get_events(source):
		if not InputMap.action_has_event(target, event):
			InputMap.action_add_event(target, event)
