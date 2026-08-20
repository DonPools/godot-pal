@tool
class_name DaoFoundationDefinition
extends ContentDefinition

@export var required_realm: CultivationRealmDefinition
@export var granted_skills: Array[SkillDefinition] = []
@export var battle_modifier: BattleBuildModifier
@export var aura_color: Color = Color(0.55, 0.8, 1.0, 1.0)
@export var max_hp_bonus: int = 0
@export var max_mp_bonus: int = 0
@export var attack_bonus: int = 0
