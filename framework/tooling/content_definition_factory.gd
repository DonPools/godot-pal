class_name ContentDefinitionFactory
extends RefCounted


static func create(
	content_type: String,
	content_id: StringName,
	options: Dictionary
) -> ContentCreationResult:
	if ProgressionDefinitionFactory.supports(content_type):
		return ProgressionDefinitionFactory.create(content_type, content_id, options)
	if ItemSkillDefinitionFactory.supports(content_type):
		return ItemSkillDefinitionFactory.create(content_type, content_id, options)
	if BattleContentDefinitionFactory.supports(content_type):
		return BattleContentDefinitionFactory.create(content_type, content_id, options)
	if WorldDefinitionFactory.supports(content_type):
		return WorldDefinitionFactory.create(content_type, content_id, options)
	if NarrativeDefinitionFactory.supports(content_type):
		return NarrativeDefinitionFactory.create(content_type, content_id, options)
	var result := ContentCreationResult.new()
	result.reject(
		"content_type_unsupported",
		"create does not support %s" % content_type,
		"",
		"type",
		content_id
	)
	return result
