@tool
class_name EnemyDefinition
extends ContentDefinition

enum CombatStyle {
	MELEE,
	RANGED,
}

@export_range(1, 9999) var max_hp: int = 30
@export_range(0, 999) var attack: int = 8
@export_range(0, 999999) var experience_reward: int = 0
@export_range(0, 99999) var money_reward: int = 0
@export var drop_item: ItemDefinition
@export_range(0, 99) var drop_quantity: int = 0
@export var character_scene: PackedScene
@export_range(0.1, 30.0, 0.1) var move_speed: float = 3.0
@export_range(0.1, 50.0, 0.1) var aggro_range: float = 8.0
@export_range(0.1, 50.0, 0.1) var attack_range: float = 1.5
@export_range(0.1, 100.0, 0.1) var leash_radius: float = 12.0
@export_range(0.0, 10.0, 0.01) var attack_windup_seconds: float = 0.35
@export_range(0.01, 10.0, 0.01) var attack_active_seconds: float = 0.1
@export_range(0.0, 10.0, 0.01) var attack_recovery_seconds: float = 0.45
@export var combat_style: CombatStyle = CombatStyle.MELEE
@export_range(0.1, 50.0, 0.1) var projectile_speed: float = 8.0
@export var battle_sprite: Texture2D
@export var strategy: EnemyStrategy
