class_name PartyState
extends RefCounted

var members: Array[ActorState] = []
var leader_id: StringName


func leader() -> ActorState:
	var selected := actor(leader_id)
	return selected if selected != null else members[0] if not members.is_empty() else null


func actor(actor_id: StringName) -> ActorState:
	for member: ActorState in members:
		if member.definition_id == actor_id:
			return member
	return null


func add_member(state: ActorState) -> bool:
	if state == null or state.definition_id.is_empty() or actor(state.definition_id) != null:
		return false
	members.append(state)
	if leader_id.is_empty():
		leader_id = state.definition_id
	return true


func to_dictionary() -> Dictionary:
	var raw_members: Array[Dictionary] = []
	for member: ActorState in members:
		raw_members.append(member.to_dictionary())
	return {"leader_id": String(leader_id), "members": raw_members}


func restore(data: Dictionary, database: ContentDatabase = null) -> bool:
	var raw_leader: Variant = data.get("leader_id")
	var raw_members: Variant = data.get("members")
	if not raw_leader is String or not raw_members is Array:
		return false
	var restored: Array[ActorState] = []
	var ids: Dictionary[StringName, bool] = {}
	for raw_member: Variant in raw_members:
		if not raw_member is Dictionary:
			return false
		var actor_id := StringName(raw_member.get("definition_id", ""))
		var definition := database.actor(actor_id) if database != null else null
		var member := ActorState.from_dictionary(raw_member, definition)
		if member == null or ids.has(member.definition_id):
			return false
		ids[member.definition_id] = true
		restored.append(member)
	var restored_leader := StringName(raw_leader)
	if restored.is_empty() or not ids.has(restored_leader):
		return false
	members = restored
	leader_id = restored_leader
	return true
