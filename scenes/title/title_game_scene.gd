class_name TitleGameScene
extends GameScene

@onready var portrait: TextureRect = $Portrait
@onready var start_button: Button = $StartButton
@onready var asset_status: Label = $AssetStatus


func enter(context: GameSceneContext, arguments: Variant) -> void:
	super.enter(context, arguments)
	portrait.texture = context.asset_library.portrait(1, Color(0.75, 0.62, 0.42))
	asset_status.text = context.asset_library.diagnostic
	start_button.pressed.connect(_start_story)
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		_start_story()
		get_viewport().set_input_as_handled()


func _start_story() -> void:
	if scene_context != null:
		scene_context.start_new_game.call()
