class_name G3AssetShowcase
extends Node3D

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.look_at(Vector3(0.0, 0.9, 0.0))
	_play_animation($HumanoidBase, &"idle", 0.25)
	_play_animation($HumanoidVariant, &"run", 0.18)
	_play_animation($MountainRaider, &"attack", 0.32)


func _play_animation(root: Node, animation_name: StringName, position: float) -> void:
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null or not player.has_animation(animation_name):
		return
	player.play(animation_name)
	player.seek(position, true)
