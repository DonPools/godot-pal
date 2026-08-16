class_name AssetLibrary
extends Node

const REQUIRED_ASSETS := [
	"res://assets/original/characters/traveler_isometric_walk_3x4.png",
	"res://assets/original/characters/shopkeeper_isometric_walk_3x4.png",
	"res://assets/original/tiles/isometric_ground_4x1.png",
	"res://assets/original/tiles/north_slope_ground_8x1.png",
	"res://assets/original/tiles/north_slope_details_6x1.png",
	"res://assets/original/props/pine_tree.png",
	"res://assets/original/props/fence_down_right.png",
	"res://assets/original/props/fence_down_left.png",
	"res://assets/original/props/roadside_shop.png",
	"res://assets/original/plants/fanqing_grass.png",
	"res://assets/original/plants/fanqing_grass_cut.png",
	"res://assets/original/props/ecology/pine_young.png",
	"res://assets/original/props/ecology/pine_mature.png",
	"res://assets/original/props/ecology/shrub_dense.png",
	"res://assets/original/props/ecology/shrub_sparse.png",
	"res://assets/original/props/ecology/rocks_small.png",
	"res://assets/original/props/ecology/rocks_large.png",
	"res://assets/original/props/ecology/fallen_log.png",
]

var diagnostic: String = "原创等距素材尚未检查"
var diagnostics: Array[Dictionary] = []


func initialize() -> void:
	diagnostics = validate_assets()
	diagnostic = (
		"原创等距素材已加载"
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
