@tool
class_name BattleEncounter
extends ContentDefinition

@export var enemies: Array[EncounterEnemy] = []
@export var allows_escape: bool = true
@export var battle_music: AudioStream
