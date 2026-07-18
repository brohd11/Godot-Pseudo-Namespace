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
		var root_dirs = NamespaceBuilder.get_config().get("root_dirs", {})
		if not root_dirs.is_empty():
			print("%s class(es) redirected by config, see 'namespace config'" % root_dirs.size())
	else:
		var new_dir = positional_args[0]
		NamespaceBuilder.set_generated_dir(new_dir)
		NamespaceBuilder.refresh_plugin_cache() # the default dir is part of the cache
	return ExitCode.OK
