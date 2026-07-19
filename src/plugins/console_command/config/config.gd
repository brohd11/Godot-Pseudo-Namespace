extends EditorConsoleSingleton.CommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const NamespaceConfig = preload("res://addons/namespace/src/namespace_config.gd")
const NamespacePlugin = preload("res://addons/namespace/plugin.gd")

const _HELP = \
"Show which classes are redirected by [namespace] config sections
Usage: namespace config (optional: --files)"

var files_flag:=false

static func get_command_name() -> String:
	return "config"

static func get_self_command_data() -> Dictionary:
	return Options.get_single_option_dict(get_command_name(), {
		&"help": _HELP
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--files")
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--files":
		files_flag = true

func _get_target_positional_count() -> int:
	return 0

func _execute(ctx:CompletionContext):
	var config = NamespaceBuilder.get_config()
	# Claims come from where the tags live, so this costs a scan. Fine here.
	var claims = NamespaceBuilder.resolve_claims_now(config)
	# Doubles as the recache path if the cache is ever out of step.
	NamespaceBuilder.refresh_plugin_cache()

	if files_flag:
		var config_files = NamespaceConfig.find_config_files()
		print("Config files found (%s):" % config_files.size())
		for path in config_files:
			print("\t%s" % path)
		print("")

	print("Default directory: %s" % NamespaceBuilder.get_generated_dir())

	var root_dirs = claims.get("root_dirs", {})
	if root_dirs.is_empty():
		print("No classes are redirected, everything builds to the default directory.")
	else:
		var sources = claims.get("sources", {})
		var sorted_roots = root_dirs.keys()
		sorted_roots.sort()
		print("Redirected classes (%s):" % sorted_roots.size())
		for root in sorted_roots:
			print("\t%s -> %s\t(%s)" % [root, root_dirs.get(root), sources.get(root, "?")])

	var output_dirs = config.get("output_dirs", [])
	print("Output directories (%s):" % output_dirs.size())
	for d in output_dirs:
		print("\t%s" % d)

	var plugin = NamespacePlugin.get_instance()
	if plugin == null:
		print_rich("[color=fedd66]Plugin instance not found, cache not refreshed.[/color]")
	else:
		var cached = plugin.namespace_classes.keys()
		cached.sort()
		print("Cached classes (%s): %s" % [cached.size(), ", ".join(cached)])

	for clash in claims.get("clashes", []):
		var message = "[color=fedd66]Claim clash for '%s': using %s, ignoring %s[/color]"
		print_rich(message % [clash.get("root"), clash.get("winner"), clash.get("loser")])

	for error in config.get("errors", []):
		var color = "fe786b" if error.get("type") == NamespaceConfig.ConfigError.FATAL else "fedd66"
		print_rich("[color=%s]%s[/color]" % [color, error.get("text")])

	return ExitCode.OK
