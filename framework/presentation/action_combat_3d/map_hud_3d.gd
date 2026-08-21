class_name MapHud3D
extends Control

const READY_COLOR := Color(1.0, 0.86, 0.48, 1.0)
const COOLDOWN_COLOR := Color(0.66, 0.69, 0.64, 1.0)
const RESOURCE_COLOR := Color(0.48, 0.78, 0.92, 1.0)
const LOCKED_COLOR := Color(0.42, 0.45, 0.43, 1.0)
const FEEDBACK_SECONDS := 0.85
const CLICK_MARKER_SECONDS := 0.42

@export_group("Action Icons")
@export var basic_attack_icon: Texture2D
@export var dodge_icon: Texture2D

@onready var objective_label: Label = $ObjectiveCard/Margin/Label
@onready var target_panel: PanelContainer = $TargetPanel
@onready var target_name_label: Label = $TargetPanel/Margin/Rows/Header/Name
@onready var target_type_label: Label = $TargetPanel/Margin/Rows/Header/Type
@onready var target_hp_bar: ProgressBar = $TargetPanel/Margin/Rows/HpBar
@onready var target_detail_label: Label = $TargetPanel/Margin/Rows/Detail
@onready var battle_panel: Control = $BattlePanel
@onready var encounter_label: Label = $BattlePanel/VitalsPanel/Margin/Rows/Encounter
@onready var controls_label: Label = $BattlePanel/Controls
@onready var hp_label: Label = $BattlePanel/VitalsPanel/Margin/Rows/Hp
@onready var hp_bar: ProgressBar = $BattlePanel/VitalsPanel/Margin/Rows/HpBar
@onready var mp_label: Label = $BattlePanel/VitalsPanel/Margin/Rows/Mp
@onready var mp_bar: ProgressBar = $BattlePanel/VitalsPanel/Margin/Rows/MpBar
@onready var interaction_panel: PanelContainer = $InteractionPrompt
@onready var interaction_label: Label = $InteractionPrompt/Margin/Label
@onready var feedback_label: Label = $ActionFeedback
@onready var ground_click_marker: Label = $GroundClickMarker
@onready var target_marker: Label = $TargetMarker

var _slots: Array[PanelContainer] = []
var _using_gamepad: bool = false
var _interaction_text: String
var _feedback_remaining: float = 0.0
var _settings: SettingsService
var _click_marker_tween: Tween


func _ready() -> void:
	_slots = [
		$BattlePanel/ActionBar/Margin/Slots/Basic,
		$BattlePanel/ActionBar/Margin/Slots/SkillOne,
		$BattlePanel/ActionBar/Margin/Slots/SkillTwo,
		$BattlePanel/ActionBar/Margin/Slots/SkillThree,
		$BattlePanel/ActionBar/Margin/Slots/Item,
		$BattlePanel/ActionBar/Margin/Slots/Dodge,
	]
	var legacy_objective := get_parent().get_node_or_null(^"Objective") as CanvasItem
	if legacy_objective != null:
		legacy_objective.visible = false
	battle_panel.visible = false
	target_panel.visible = false
	interaction_panel.visible = false
	feedback_label.visible = false
	ground_click_marker.visible = false
	target_marker.visible = false
	_set_slot(
		_slots[0], tr("UI_INPUT_MOUSE_LEFT"), basic_attack_icon,
		tr("UI_HUD_BASIC_ATTACK"), tr("UI_HUD_PURSUIT"), READY_COLOR
	)
	_set_slot(
		_slots[1], tr("UI_INPUT_MOUSE_RIGHT"), null,
		tr("UI_HUD_NOT_CONFIGURED"), "—", LOCKED_COLOR
	)
	_set_slot(_slots[2], "1", null, tr("UI_HUD_NOT_CONFIGURED"), "—", LOCKED_COLOR)
	_set_slot(_slots[3], "2", null, tr("UI_HUD_NOT_CONFIGURED"), "—", LOCKED_COLOR)
	_set_slot(_slots[4], "Q", null, tr("UI_HUD_NOT_CONFIGURED"), "×0", LOCKED_COLOR)
	_set_slot(
		_slots[5], tr("UI_INPUT_SPACE"), dodge_icon,
		tr("UI_HUD_DODGE"), tr("UI_HUD_READY"), READY_COLOR
	)


func _process(delta: float) -> void:
	if _feedback_remaining <= 0.0:
		return
	_feedback_remaining = maxf(_feedback_remaining - delta, 0.0)
	if _feedback_remaining <= 0.0:
		feedback_label.visible = false


func configure(settings: SettingsService) -> void:
	_settings = settings
	_refresh_control_text()
	_refresh_interaction_text()


func show_objective(text: String) -> void:
	objective_label.text = text
	$ObjectiveCard.visible = not text.is_empty()


func set_input_device(using_gamepad: bool) -> void:
	if _using_gamepad == using_gamepad:
		return
	_using_gamepad = using_gamepad
	_refresh_control_text()
	_refresh_interaction_text()


func show_battle() -> void:
	battle_panel.visible = true
	interaction_panel.visible = false
	_refresh_control_text()


func hide_battle() -> void:
	battle_panel.visible = false
	target_panel.visible = false
	feedback_label.visible = false
	_feedback_remaining = 0.0
	hide_target()
	_refresh_interaction_text()


func show_interaction(text: String) -> void:
	_interaction_text = text
	_refresh_interaction_text()


func refresh_battle(
	session: BattleSession,
	actor_state: ActorState,
	database: ContentDatabase,
	target_actor: BattleActorState = null,
	target_definition: EnemyDefinition = null
) -> void:
	if session == null or session.player == null:
		return
	var player := session.player
	hp_bar.max_value = maxf(float(player.max_hp), 1.0)
	hp_bar.value = player.hp
	hp_label.text = tr("UI_HUD_HP_FORMAT") % [player.hp, player.max_hp]
	mp_bar.max_value = maxf(float(player.max_mp), 1.0)
	mp_bar.value = player.mp
	mp_label.text = tr("UI_HUD_QI_FORMAT") % [player.mp, player.max_mp]
	var alive := 0
	for enemy: BattleActorState in session.enemies:
		if enemy.is_alive():
			alive += 1
	var realm := database.realm(actor_state.realm_id) if actor_state != null else null
	encounter_label.text = tr("UI_HUD_ENCOUNTER_FORMAT") % [
		realm.display_name if realm != null else "",
		actor_state.realm_layer if actor_state != null else 0,
		alive,
	]
	_refresh_action_slots(session, actor_state, database)
	_refresh_target(target_actor, target_definition)


func show_ground_click(screen_position: Vector2) -> void:
	if _click_marker_tween != null and _click_marker_tween.is_valid():
		_click_marker_tween.kill()
	ground_click_marker.position = screen_position - ground_click_marker.size * 0.5
	ground_click_marker.modulate.a = 1.0
	ground_click_marker.scale = Vector2(0.7, 0.7)
	ground_click_marker.pivot_offset = ground_click_marker.size * 0.5
	ground_click_marker.visible = true
	_click_marker_tween = create_tween()
	_click_marker_tween.set_parallel(true)
	_click_marker_tween.tween_property(
		ground_click_marker, "scale", Vector2.ONE, CLICK_MARKER_SECONDS
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_click_marker_tween.tween_property(
		ground_click_marker, "modulate:a", 0.0, CLICK_MARKER_SECONDS
	)
	_click_marker_tween.chain().tween_callback(
		func() -> void: ground_click_marker.visible = false
	)


func show_target(screen_position: Vector2) -> void:
	target_marker.position = screen_position - target_marker.size * 0.5
	target_marker.visible = true


func hide_target() -> void:
	target_marker.visible = false


func show_rejection(rejection: BattleActionRequestResult.Rejection) -> void:
	var message := ""
	match rejection:
		BattleActionRequestResult.Rejection.ACTOR_BUSY:
			message = tr("UI_HUD_REJECT_BUSY")
		BattleActionRequestResult.Rejection.COOLDOWN:
			message = tr("UI_HUD_REJECT_COOLDOWN")
		BattleActionRequestResult.Rejection.INSUFFICIENT_RESOURCE:
			message = tr("UI_HUD_REJECT_QI")
		BattleActionRequestResult.Rejection.SKILL_UNAVAILABLE:
			message = tr("UI_HUD_REJECT_SKILL")
		BattleActionRequestResult.Rejection.ITEM_UNAVAILABLE:
			message = tr("UI_HUD_REJECT_ITEM")
		BattleActionRequestResult.Rejection.TARGET_INVALID:
			message = tr("UI_HUD_REJECT_TARGET")
		BattleActionRequestResult.Rejection.ACTION_INVALID:
			message = tr("UI_HUD_REJECT_ACTION")
	if not message.is_empty():
		show_notice(message)


func show_notice(message: String) -> void:
	if message.is_empty():
		return
	feedback_label.text = message
	feedback_label.visible = true
	_feedback_remaining = FEEDBACK_SECONDS


func _refresh_action_slots(
	session: BattleSession,
	actor_state: ActorState,
	database: ContentDatabase
) -> void:
	var player := session.player
	var basic_cooldown := player.cooldown_remaining(BattleSession.BASIC_ATTACK_ID)
	_set_slot(
		_slots[0], _binding_label(&"combat_attack", true, tr("UI_INPUT_MOUSE_LEFT")),
		basic_attack_icon, tr("UI_HUD_BASIC_ATTACK"),
		tr("UI_HUD_COOLDOWN_FORMAT") % basic_cooldown
		if basic_cooldown > 0.0 else tr("UI_HUD_PURSUIT"),
		COOLDOWN_COLOR if basic_cooldown > 0.0 else READY_COLOR
	)
	for index: int in range(3):
		var key := _binding_label(
			[&"combat_skill_one", &"combat_skill_two", &"combat_skill_three"][index],
			index == 0,
			[tr("UI_INPUT_MOUSE_RIGHT"), "1", "2"][index]
		)
		if index >= player.allowed_skill_ids.size() or player.allowed_skill_ids[index].is_empty():
			_set_slot(
				_slots[index + 1], key, null,
				tr("UI_HUD_NOT_CONFIGURED"), "—", LOCKED_COLOR
			)
			continue
		var skill := database.skill(player.allowed_skill_ids[index])
		if skill == null:
			_set_slot(_slots[index + 1], key, null, tr("UI_HUD_UNKNOWN"), "—", LOCKED_COLOR)
			continue
		var cooldown := player.cooldown_remaining(skill.id)
		var state := tr("UI_HUD_QI_COST_FORMAT") % skill.mp_cost
		var color := READY_COLOR
		if cooldown > 0.0:
			state = tr("UI_HUD_COOLDOWN_FORMAT") % cooldown
			color = COOLDOWN_COLOR
		elif player.mp < skill.mp_cost:
			state = tr("UI_HUD_QI_LOW")
			color = RESOURCE_COLOR
		_set_slot(_slots[index + 1], key, skill.icon, skill.display_name, state, color)
	var item := database.item(player.battle_item_id) if not player.battle_item_id.is_empty() else null
	var quantity := session.battle_item_quantity()
	if item == null:
		_set_slot(
			_slots[4], _binding_label(&"combat_item", false, "Q"), null,
			tr("UI_HUD_NOT_CONFIGURED"), "×0", LOCKED_COLOR
		)
	else:
		_set_slot(
			_slots[4], _binding_label(&"combat_item", false, "Q"), item.icon,
			item.display_name, "×%d" % quantity,
			READY_COLOR if quantity > 0 else LOCKED_COLOR
		)
	var dodge_cooldown := player.cooldown_remaining(BattleSession.DODGE_ID)
	_set_slot(
		_slots[5], _binding_label(&"combat_dodge", false, tr("UI_INPUT_SPACE")),
		dodge_icon, tr("UI_HUD_DODGE"),
		tr("UI_HUD_COOLDOWN_FORMAT") % dodge_cooldown
		if dodge_cooldown > 0.0 else tr("UI_HUD_READY"),
		COOLDOWN_COLOR if dodge_cooldown > 0.0 else READY_COLOR
	)


func _refresh_target(
	target_actor: BattleActorState,
	target_definition: EnemyDefinition
) -> void:
	target_panel.visible = target_actor != null and target_definition != null and target_actor.is_alive()
	if not target_panel.visible:
		return
	target_name_label.text = target_definition.display_name
	target_type_label.text = (
		tr("UI_HUD_BOSS") if target_definition.is_boss else tr("UI_HUD_TARGET")
	)
	target_hp_bar.max_value = maxf(float(target_actor.max_hp), 1.0)
	target_hp_bar.value = target_actor.hp
	target_detail_label.text = (
		tr("UI_HUD_STAGGER_FORMAT") % target_actor.stagger_remaining_seconds
		if target_actor.stagger_remaining_seconds > 0.0
		else tr("UI_HUD_HP_FORMAT") % [target_actor.hp, target_actor.max_hp]
	)


func _set_slot(
	slot: PanelContainer,
	key_text: String,
	icon_texture: Texture2D,
	name_text: String,
	state_text: String,
	color: Color
) -> void:
	(slot.get_node(^"Rows/Key") as Label).text = key_text
	var icon := slot.get_node(^"Rows/Icon") as TextureRect
	icon.texture = icon_texture
	icon.modulate = color
	(slot.get_node(^"Rows/Name") as Label).text = name_text
	(slot.get_node(^"Rows/State") as Label).text = state_text
	for child_name: StringName in [&"Key", &"Name", &"State"]:
		(slot.get_node(NodePath("Rows/%s" % child_name)) as Label).modulate = color


func _refresh_control_text() -> void:
	if controls_label == null:
		return
	controls_label.visible = false


func _refresh_interaction_text() -> void:
	if interaction_panel == null:
		return
	interaction_panel.visible = not battle_panel.visible and not _interaction_text.is_empty()
	if interaction_panel.visible:
		var interaction_key := (
			_binding_label(&"interact", false, "A")
			if _using_gamepad
			else _binding_label(&"combat_attack", true, tr("UI_INPUT_MOUSE_LEFT"))
		)
		interaction_label.text = "[%s]  %s" % [
			interaction_key,
			_interaction_text,
		]


func _binding_label(action: StringName, prefer_mouse: bool, fallback: String) -> String:
	if _settings == null:
		return fallback
	var slot := (
		SettingsService.BindingSlot.GAMEPAD
		if _using_gamepad
		else SettingsService.BindingSlot.MOUSE
		if prefer_mouse
		else SettingsService.BindingSlot.KEYBOARD
	)
	var label := _settings.binding_label(action, slot)
	if label == "—" and not _using_gamepad:
		label = _settings.binding_label(
			action,
			SettingsService.BindingSlot.KEYBOARD
			if prefer_mouse
			else SettingsService.BindingSlot.MOUSE
		)
	return label if label != "—" else fallback
