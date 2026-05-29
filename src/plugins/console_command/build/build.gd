extends EditorConsoleSingleton.CommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const _HELP = \
"Generate namespace files for current tags
Usage: namespace build"

static func get_command_name() -> String:
	return "build"

static func get_self_command_data() -> Dictionary:
	return Options.get_single_option_dict(get_command_name(), {
		&"help": _HELP
	})

func _execute(ctx:CompletionContext):
	NamespaceBuilder.build_files()
