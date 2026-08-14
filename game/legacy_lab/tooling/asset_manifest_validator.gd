class_name AssetManifestValidator
extends RefCounted

const SCHEMA_VERSION := 1
const REQUIRED_PROFILE := "framework-lab"
const HASH_LENGTH := 64

const KIND_EXTENSIONS := {
	"bitmap_font": "fnt",
	"bitmap_font_texture": "png",
	"field_character_atlas": "png",
	"music": "wav",
	"palette": "png",
	"portrait": "png",
	"sound_effect": "wav",
	"tile_atlas": "png",
	"ui_atlas": "png",
}

const REQUIRED_ASSETS := {
	"MUS.MKF:31": "music",
	"VOC.MKF:78": "sound_effect",
	"VOC.MKF:98": "sound_effect",
	"WOR16.ASC:-1": "bitmap_font",
	"WOR16.FON:-1": "bitmap_font_texture",
	"MGO.MKF:2": "field_character_atlas",
	"MGO.MKF:21": "field_character_atlas",
	"MGO.MKF:29": "field_character_atlas",
	"MGO.MKF:30": "field_character_atlas",
	"MGO.MKF:207": "field_character_atlas",
	"PAT.MKF:0": "palette",
	"RGM.MKF:1": "portrait",
	"RGM.MKF:3": "portrait",
	"RGM.MKF:6": "portrait",
	"RGM.MKF:55": "portrait",
	"RGM.MKF:59": "portrait",
	"GOP.MKF:10": "tile_atlas",
	"GOP.MKF:12": "tile_atlas",
	"DATA.MKF:9": "ui_atlas",
	"DATA.MKF:12": "ui_atlas",
}


func validate_file(manifest_path: String, generated_root: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	if not FileAccess.file_exists(manifest_path):
		diagnostics.append(_diagnostic(
			"manifest_missing",
			"required generated asset manifest does not exist",
			manifest_path,
			""
		))
		return {"manifest": {}, "diagnostics": diagnostics}
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		diagnostics.append(_diagnostic(
			"manifest_open_failed",
			"generated asset manifest could not be opened",
			manifest_path,
			""
		))
		return {"manifest": {}, "diagnostics": diagnostics}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		diagnostics.append(_diagnostic(
			"manifest_invalid_json",
			"generated asset manifest is invalid JSON: %s" % json.get_error_message(),
			manifest_path,
			""
		))
		return {"manifest": {}, "diagnostics": diagnostics}
	var manifest: Dictionary = json.data
	diagnostics.append_array(validate_data(manifest, generated_root, manifest_path))
	return {"manifest": manifest, "diagnostics": diagnostics}


func validate_data(
	manifest: Dictionary,
	generated_root: String,
	manifest_path: String = "res://generated/manifest.json"
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if int(manifest.get("schema_version", -1)) != SCHEMA_VERSION:
		diagnostics.append(_diagnostic(
			"manifest_schema_unsupported",
			"generated asset manifest must use schema version %d" % SCHEMA_VERSION,
			manifest_path,
			"schema_version"
		))
	if String(manifest.get("export_profile", "")) != REQUIRED_PROFILE:
		diagnostics.append(_diagnostic(
			"manifest_profile_invalid",
			"generated asset manifest must use profile %s" % REQUIRED_PROFILE,
			manifest_path,
			"export_profile"
		))
	for field: String in ["source_variant", "exporter_version"]:
		if String(manifest.get(field, "")).is_empty():
			diagnostics.append(_diagnostic(
				"manifest_field_missing",
				"generated asset manifest field is required: %s" % field,
				manifest_path,
				field
			))
	_validate_source_hashes(manifest.get("source_hashes"), manifest_path, diagnostics)
	var raw_assets: Variant = manifest.get("assets")
	if not raw_assets is Array:
		diagnostics.append(_diagnostic(
			"manifest_assets_invalid",
			"generated asset manifest must contain an assets array",
			manifest_path,
			"assets"
		))
		return diagnostics
	var assets: Array = raw_assets
	if assets.is_empty():
		diagnostics.append(_diagnostic(
			"manifest_assets_empty",
			"generated asset manifest contains no assets",
			manifest_path,
			"assets"
		))
		return diagnostics
	var seen_sources: Dictionary[String, bool] = {}
	var seen_paths: Dictionary[String, bool] = {}
	var kinds_by_source: Dictionary[String, String] = {}
	for index: int in range(assets.size()):
		_validate_asset(
			assets[index],
			index,
			generated_root,
			manifest_path,
			seen_sources,
			seen_paths,
			kinds_by_source,
			diagnostics
		)
	for source_key: String in REQUIRED_ASSETS:
		if not kinds_by_source.has(source_key):
			diagnostics.append(_diagnostic(
				"manifest_required_asset_missing",
				"framework-lab manifest is missing required asset %s" % source_key,
				manifest_path,
				"assets",
				source_key
			))
		elif kinds_by_source[source_key] != REQUIRED_ASSETS[source_key]:
			diagnostics.append(_diagnostic(
				"manifest_required_asset_kind_invalid",
				"required asset %s must use kind %s" % [
					source_key,
					REQUIRED_ASSETS[source_key],
				],
				manifest_path,
				"assets",
				source_key
			))
	return diagnostics


func _validate_source_hashes(
	raw_hashes: Variant,
	manifest_path: String,
	diagnostics: Array[Dictionary]
) -> void:
	if not raw_hashes is Dictionary:
		diagnostics.append(_diagnostic(
			"manifest_source_hashes_invalid",
			"generated asset manifest must contain source_hashes",
			manifest_path,
			"source_hashes"
		))
		return
	var hashes: Dictionary = raw_hashes
	for source_file: Variant in hashes:
		if not source_file is String or not _is_sha256(String(hashes[source_file])):
			diagnostics.append(_diagnostic(
				"manifest_source_hash_invalid",
				"source hash must be a lowercase SHA-256 value",
				manifest_path,
				"source_hashes.%s" % source_file
			))


func _validate_asset(
	raw_asset: Variant,
	index: int,
	generated_root: String,
	manifest_path: String,
	seen_sources: Dictionary[String, bool],
	seen_paths: Dictionary[String, bool],
	kinds_by_source: Dictionary[String, String],
	diagnostics: Array[Dictionary]
) -> void:
	var field_prefix := "assets[%d]" % index
	if not raw_asset is Dictionary:
		diagnostics.append(_diagnostic(
			"manifest_asset_invalid",
			"asset entry must be an object",
			manifest_path,
			field_prefix
		))
		return
	var asset: Dictionary = raw_asset
	var kind := String(asset.get("kind", ""))
	if not KIND_EXTENSIONS.has(kind):
		diagnostics.append(_diagnostic(
			"manifest_asset_kind_invalid",
			"asset kind is not supported: %s" % kind,
			manifest_path,
			field_prefix + ".kind"
		))
	var raw_source: Variant = asset.get("source")
	var source_key := ""
	if not raw_source is Dictionary:
		diagnostics.append(_diagnostic(
			"manifest_asset_source_invalid",
			"asset source must be an object",
			manifest_path,
			field_prefix + ".source"
		))
	else:
		var source: Dictionary = raw_source
		var source_file := String(source.get("file", ""))
		if source_file.is_empty():
			diagnostics.append(_diagnostic(
				"manifest_asset_source_file_missing",
				"asset source file is required",
				manifest_path,
				field_prefix + ".source.file"
			))
		else:
			source_key = "%s:%d" % [source_file, int(source.get("chunk", -1))]
			if seen_sources.has(source_key):
				diagnostics.append(_diagnostic(
					"manifest_asset_source_duplicate",
					"asset source is repeated: %s" % source_key,
					manifest_path,
					field_prefix + ".source",
					source_key
				))
			else:
				seen_sources[source_key] = true
				kinds_by_source[source_key] = kind
	var relative_path := String(asset.get("path", ""))
	if not _is_safe_relative_path(relative_path):
		diagnostics.append(_diagnostic(
			"manifest_asset_path_invalid",
			"asset path must be a normalized path below generated/: %s" % relative_path,
			manifest_path,
			field_prefix + ".path",
			source_key
		))
		return
	if seen_paths.has(relative_path):
		diagnostics.append(_diagnostic(
			"manifest_asset_path_duplicate",
			"asset output path is repeated: %s" % relative_path,
			manifest_path,
			field_prefix + ".path",
			source_key
		))
	else:
		seen_paths[relative_path] = true
	if KIND_EXTENSIONS.has(kind):
		var expected_extension := String(KIND_EXTENSIONS[kind])
		if relative_path.get_extension().to_lower() != expected_extension:
			diagnostics.append(_diagnostic(
				"manifest_asset_extension_invalid",
				"asset kind %s requires a .%s file" % [kind, expected_extension],
				manifest_path,
				field_prefix + ".path",
				source_key
			))
	var asset_path := generated_root.path_join(relative_path)
	if not FileAccess.file_exists(asset_path):
		diagnostics.append(_diagnostic(
			"manifest_asset_file_missing",
			"generated asset file does not exist: %s" % relative_path,
			asset_path,
			field_prefix + ".path",
			source_key
		))
		return
	if KIND_EXTENSIONS.has(kind) and not _file_matches_extension(asset_path, relative_path):
		diagnostics.append(_diagnostic(
			"manifest_asset_type_invalid",
			"generated asset content does not match its file type: %s" % relative_path,
			asset_path,
			field_prefix + ".path",
			source_key
		))
	var expected_hash := String(asset.get("sha256", ""))
	if not _is_sha256(expected_hash):
		diagnostics.append(_diagnostic(
			"manifest_asset_hash_invalid",
			"asset sha256 must be a lowercase SHA-256 value",
			manifest_path,
			field_prefix + ".sha256",
			source_key
		))
	elif FileAccess.get_sha256(asset_path) != expected_hash:
		diagnostics.append(_diagnostic(
			"manifest_asset_hash_mismatch",
			"generated asset hash does not match manifest: %s" % relative_path,
			asset_path,
			field_prefix + ".sha256",
			source_key
		))
	if not asset.get("metadata") is Dictionary:
		diagnostics.append(_diagnostic(
			"manifest_asset_metadata_invalid",
			"asset metadata must be an object",
			manifest_path,
			field_prefix + ".metadata",
			source_key
		))


func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.is_absolute_path() or path.contains("\\"):
		return false
	if path.begins_with(".") or path.contains("/../") or path.contains("/./"):
		return false
	return path.simplify_path() == path


func _is_sha256(value: String) -> bool:
	if value.length() != HASH_LENGTH or value != value.to_lower():
		return false
	return value.is_valid_hex_number(false)


func _file_matches_extension(path: String, relative_path: String) -> bool:
	var extension := relative_path.get_extension().to_lower()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if extension == "png":
		var signature := file.get_buffer(8)
		file.close()
		return signature == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	if extension == "wav":
		var header := file.get_buffer(12)
		file.close()
		return (
			header.size() == 12
			and header.slice(0, 4).get_string_from_ascii() == "RIFF"
			and header.slice(8, 12).get_string_from_ascii() == "WAVE"
		)
	if extension == "fnt":
		var first_line := file.get_line()
		file.close()
		return first_line.begins_with("info ")
	file.close()
	return false


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	source: String = ""
) -> Dictionary:
	var result := {
		"code": code,
		"message": message,
		"file": file,
		"field": field,
	}
	if not source.is_empty():
		result["source"] = source
	return result
