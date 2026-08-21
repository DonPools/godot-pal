class_name TitleGameScene
extends GameScene

@onready var portrait: TextureRect = $Portrait
@onready var eyebrow_label: Label = $Eyebrow
@onready var title_label: Label = $Title
@onready var subtitle_label: Label = $Subtitle
@onready var role_label: Label = $RoleLabel
@onready var journey_label: Label = $JourneyLabel
@onready var portrait_caption: Label = $PortraitCaption
@onready var menu_label: Label = $MenuPanel/MenuLabel
@onready var menu_hint: Label = $MenuHint
@onready var start_button: Button = $StartButton
@onready var load_button: Button = $LoadButton
@onready var settings_button: Button = $SettingsButton
@onready var quit_button: Button = $QuitButton
@onready var asset_status: Label = $AssetStatus


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	var portrait_source := load(
		"res://assets/original/3d/title_traveler_portrait.png"
	) as Texture2D
	var portrait_crop := AtlasTexture.new()
	portrait_crop.atlas = portrait_source
	portrait_crop.region = Rect2(54.0, 0.0, 48.0, 98.0)
	portrait.texture = portrait_crop
	asset_status.text = context.startup_diagnostic
	asset_status.visible = not context.startup_diagnostics.is_empty()
	start_button.pressed.connect(_start_new_game)
	load_button.pressed.connect(_open_load)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(_quit_game)
	_refresh_text()
	start_button.grab_focus()


func resume_scene(result: Variant = null) -> void:
	super.resume_scene(result)
	_refresh_text()


func _start_new_game() -> void:
	if scene_context != null:
		scene_context.request_new_game()


func _open_load() -> void:
	if scene_context != null and scene_context.save_load_scene != null:
		scene_context.scene_stack.push(scene_context.save_load_scene, {"save": false})


func _open_settings() -> void:
	if scene_context != null and scene_context.settings_scene != null:
		scene_context.scene_stack.push(scene_context.settings_scene)


func _quit_game() -> void:
	get_tree().quit()


func _refresh_text() -> void:
	eyebrow_label.text = tr("UI_TITLE_EYEBROW")
	title_label.text = tr("UI_GAME_TITLE")
	subtitle_label.text = tr("UI_GAME_SUBTITLE")
	role_label.text = tr("UI_TITLE_ROLE")
	journey_label.text = tr("UI_TITLE_JOURNEY")
	portrait_caption.text = tr("UI_TITLE_CAPTION")
	menu_label.text = tr("UI_TITLE_MENU")
	menu_hint.text = tr("UI_TITLE_CONFIRM_HINT")
	start_button.text = tr("UI_START")
	load_button.text = tr("UI_LOAD")
	settings_button.text = tr("UI_SETTINGS")
	quit_button.text = tr("UI_QUIT")
