extends EditorConsoleSingleton.CommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const _HELP = \
"Generate namespace files for current tags
Usage: namespace build"

static func get_command_name() -> String:
	return "build"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP
	})

func _execute(ctx:Context):
	# Holds the console until the confirm dialogs are answered.
	await NamespaceBuilder.build_files()
	return ExitCode.OK
