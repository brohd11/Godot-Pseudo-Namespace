extends EditorConsoleSingleton.CommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const _HELP = \
"Display or set the directory the files will be generated in
Usage: namespace dir (optional: --set <new_dir>)"

var set_flag:=false

static func get_command_name() -> String:
	return "dir"

static func get_self_command_data() -> Dictionary:
	return Options.get_single_option_dict(get_command_name(), {
		&"help": _HELP
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--set")
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--set":
		set_flag = true

func _get_target_positional_count() -> int:
	if set_flag:
		return 1
	return 0

func _execute(ctx:CompletionContext):
	if not set_flag:
		print(NamespaceBuilder.get_generated_dir())
	else:
		var new_dir = positional_args[0]
		NamespaceBuilder.set_generated_dir(new_dir)
	return ExitCode.OK
