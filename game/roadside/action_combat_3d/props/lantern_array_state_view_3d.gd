class_name LanternArrayStateView3D
extends WorldStateView3D

@onready var array_light: OmniLight3D = $ArrayLight
@onready var state_label: Label3D = $StateLabel
@onready var shortcut_root: Node3D = $ShortcutRoot

var _game_run: GameRun


func configure_world_state(game_run: GameRun, _map_id: StringName) -> void:
	_game_run = game_run
	refresh_world_state()


func refresh_world_state() -> void:
	if _game_run == null:
		return
	var restored := _game_run.flags.is_set(LanternPassStory.ARRAY_RESTORED)
	var salvaged := _game_run.flags.is_set(LanternPassStory.ARRAY_SALVAGED)
	array_light.light_energy = 3.2 if restored else 0.35 if salvaged else 1.0
	array_light.light_color = (
		Color(0.46, 1.0, 0.68, 1)
		if restored
		else Color(0.38, 0.42, 0.36, 1)
	)
	state_label.text = "阵灯已修复" if restored else "阵芯已拆" if salvaged else "阵灯待处理"
	shortcut_root.visible = restored
	shortcut_root.process_mode = (
		Node.PROCESS_MODE_INHERIT if restored else Node.PROCESS_MODE_DISABLED
	)
