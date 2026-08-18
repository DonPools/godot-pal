class_name TitleGameScene
extends GameScene

@onready var portrait: TextureRect = $Portrait
@onready var title_label: Label = $Title
@onready var subtitle_label: Label = $Subtitle
@onready var start_button: Button = $StartButton
@onready var load_button: Button = $LoadButton
@onready var settings_button: Button = $SettingsButton
@onready var asset_status: Label = $AssetStatus


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	portrait.texture = load(
		"res://assets/original/3d/title_traveler_portrait.png"
	) as Texture2D
	asset_status.text = context.asset_library.diagnostic
	start_button.pressed.connect(_start_story)
	load_button.pressed.connect(_open_load)
	settings_button.pressed.connect(_open_settings)
	_refresh_text()
	start_button.grab_focus()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	_refresh_text()


func _start_story() -> void:
	if scene_context != null:
		scene_context.start_new_game.call()


func _open_load() -> void:
	if scene_context != null and scene_context.save_load_scene != null:
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": false})


func _open_settings() -> void:
	if scene_context != null and scene_context.settings_scene != null:
		scene_context.scene_stack.push(scene_context.settings_scene)


func _refresh_text() -> void:
	title_label.text = tr("UI_GAME_TITLE")
	subtitle_label.text = tr("UI_GAME_SUBTITLE")
	start_button.text = tr("UI_START")
	load_button.text = tr("UI_LOAD")
	settings_button.text = tr("UI_SETTINGS")
