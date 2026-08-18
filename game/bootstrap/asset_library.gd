class_name AssetLibrary
extends Node

const REQUIRED_ASSETS := [
	"res://assets/original/3d/manifest.json",
	"res://assets/original/3d/models/humanoid_base.glb",
	"res://assets/original/3d/models/humanoid_variant.glb",
	"res://assets/original/3d/models/mountain_raider.glb",
	"res://assets/original/3d/models/fanqing_grass.glb",
	"res://assets/original/3d/models/fanqing_grass_cut.glb",
	"res://assets/original/3d/models/pine_tree.glb",
	"res://assets/original/3d/models/rocks_cluster.glb",
	"res://assets/original/3d/models/roadside_hut.glb",
	"res://assets/original/3d/models/wood_fence.glb",
	"res://assets/original/3d/title_traveler_portrait.png",
	"res://assets/original/audio/mountain_path.wav",
	"res://assets/original/audio/sword_hit.wav",
	"res://assets/original/audio/dodge.wav",
	"res://assets/original/audio/victory.wav",
	"res://assets/original/audio/escaped.wav",
	"res://assets/original/audio/defeat.wav",
]

var diagnostic: String = "原创 3D 素材尚未检查"
var diagnostics: Array[Dictionary] = []


func initialize() -> void:
	diagnostics = validate_assets()
	diagnostic = (
		"原创 3D 素材已加载"
		if diagnostics.is_empty()
		else "缺少 %d 个原创素材" % diagnostics.size()
	)
	for entry: Dictionary in diagnostics:
		push_error(JSON.stringify(entry))


static func validate_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for path: String in REQUIRED_ASSETS:
		if not ResourceLoader.exists(path):
			result.append({
				"code": "original_asset_missing",
				"message": "required original asset is missing",
				"file": path,
			})
	return result
