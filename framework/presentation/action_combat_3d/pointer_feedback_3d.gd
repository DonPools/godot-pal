class_name PointerFeedback3D
extends Node3D

enum DestinationKind {
	MOVE,
	INTERACT,
	UNREACHABLE,
}

const DESTINATION_DURATION := 0.42
const FAILURE_DURATION := 0.8

@onready var move_marker: MeshInstance3D = $MoveMarker
@onready var interact_marker: MeshInstance3D = $InteractMarker
@onready var failure_marker: MeshInstance3D = $FailureMarker
@onready var failure_label: Label3D = $FailureLabel
@onready var target_ring: MeshInstance3D = $TargetRing

var _destination_tween: Tween
var _target: Node3D
var _target_radius: float = 1.0
var _pulse_time: float = 0.0


func _ready() -> void:
	move_marker.visible = false
	interact_marker.visible = false
	failure_marker.visible = false
	failure_label.visible = false
	target_ring.visible = false


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		clear_target()
		return
	_pulse_time += delta
	target_ring.global_position = _target.global_position + Vector3.UP * 0.07
	var pulse := 1.0 + sin(_pulse_time * 6.0) * 0.055
	target_ring.scale = Vector3.ONE * _target_radius * pulse


func show_destination(world_position: Vector3, kind: DestinationKind) -> void:
	if _destination_tween != null and _destination_tween.is_valid():
		_destination_tween.kill()
	move_marker.visible = false
	interact_marker.visible = false
	failure_marker.visible = false
	failure_label.visible = false
	var marker := _marker_for_kind(kind)
	marker.global_position = world_position + Vector3.UP * 0.08
	marker.scale = Vector3.ONE * 0.58
	marker.transparency = 0.0
	marker.visible = true
	if kind == DestinationKind.UNREACHABLE:
		failure_label.global_position = world_position + Vector3.UP * 0.42
		failure_label.modulate.a = 1.0
		failure_label.visible = true
	_destination_tween = create_tween()
	_destination_tween.set_parallel(true)
	_destination_tween.tween_property(
		marker,
		"scale",
		Vector3.ONE * (1.3 if kind == DestinationKind.UNREACHABLE else 1.0),
		FAILURE_DURATION if kind == DestinationKind.UNREACHABLE else DESTINATION_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_destination_tween.tween_property(
		marker,
		"transparency",
		1.0,
		FAILURE_DURATION if kind == DestinationKind.UNREACHABLE else DESTINATION_DURATION
	)
	if kind == DestinationKind.UNREACHABLE:
		_destination_tween.tween_property(
			failure_label,
			"modulate:a",
			0.0,
			FAILURE_DURATION
		)
	_destination_tween.chain().tween_callback(_hide_destination_markers)


func set_target(target: Node3D, radius: float = 1.0) -> void:
	var normalized_radius := maxf(radius, 0.65)
	if _target == target and is_equal_approx(_target_radius, normalized_radius):
		return
	_target = target
	_target_radius = normalized_radius
	_pulse_time = 0.0
	target_ring.visible = target != null


func clear_target() -> void:
	_target = null
	target_ring.visible = false


func _marker_for_kind(kind: DestinationKind) -> MeshInstance3D:
	match kind:
		DestinationKind.INTERACT:
			return interact_marker
		DestinationKind.UNREACHABLE:
			return failure_marker
	return move_marker


func _hide_destination_markers() -> void:
	move_marker.visible = false
	interact_marker.visible = false
	failure_marker.visible = false
	failure_label.visible = false
