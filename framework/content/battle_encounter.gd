@tool
class_name BattleEncounter
extends ContentDefinition

@export var enemies: Array[EncounterEnemy] = []
@export var allows_escape: bool = true
@export_range(1.0, 100.0, 0.5) var encounter_radius: float = 10.0
@export_range(1.0, 200.0, 0.5) var leash_radius: float = 14.0
@export var reward_policy: RewardPolicy.Value = RewardPolicy.Value.ALL_OR_NOTHING
@export var battle_music: AudioStream
