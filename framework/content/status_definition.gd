@tool
class_name StatusDefinition
extends ContentDefinition

@export_range(0.01, 600.0, 0.01) var duration_seconds: float = 1.0
@export_range(0.01, 600.0, 0.01) var tick_interval_seconds: float = 1.0
@export_range(0, 999) var periodic_damage: int = 0
