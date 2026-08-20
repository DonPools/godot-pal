@tool
class_name BasicChainWaveModifier
extends BattleBuildModifier

@export_range(2, 9) var chain_length: int = 3
@export_range(1, 9999) var wave_damage: int = 14


func apply_to(snapshot: BattleBuildSnapshot) -> void:
	if snapshot == null:
		return
	snapshot.basic_chain_length = chain_length
	snapshot.basic_chain_wave_damage = wave_damage


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if chain_length < 2 or wave_damage < 1:
		errors.append("basic chain wave modifier requires a chain and positive damage")
	return errors
