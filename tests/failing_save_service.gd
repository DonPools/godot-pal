class_name FailingSaveService
extends SaveService

var fail_next_temporary_install: bool = false


func _rename_absolute(from: String, to: String) -> Error:
	if fail_next_temporary_install and from.ends_with(".tmp"):
		fail_next_temporary_install = false
		return ERR_CANT_CREATE
	return super._rename_absolute(from, to)
