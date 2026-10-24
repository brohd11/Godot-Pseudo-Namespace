extends EditorConsoleSingleton.CommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const _HELP = \
"Execute commands for Namespace plugin"

static func get_command_name() -> String:
	return "namespace"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP
	})
