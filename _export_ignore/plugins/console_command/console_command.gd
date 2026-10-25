extends EditorConsoleSingleton.CommandBase # placeholder, swapped by RuntimeExtend

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const NamespaceSingleton = preload("res://addons/namespace/src/namespace_singleton.gd")

const _DIR = "res://addons/namespace/_export_ignore/plugins/console_command"
const _SUBCOMMANDS = ["build", "config", "dir"]

## Built once: completion asks for these on every keystroke.
static var _commands := {}

const _HELP = \
"Execute commands for Namespace plugin"

static func get_command_name() -> String:
	return "namespace"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP
	})

## gdsh would load() the subcommand files straight from disk, where their placeholder
## extends can't resolve. Built against this script's base instead, which is already
## the resolved CommandBase.
func _get_commands() -> Dictionary:
	if _commands.is_empty():
		var base = get_script().get_base_script()
		for command_name in _SUBCOMMANDS:
			var script = NamespaceSingleton.RuntimeExtend.build(_DIR.path_join(command_name).path_join(command_name + ".gd"), base)
			if script:
				Options.add_command_script_to_dict(script, _commands)
		_commands = Utils.sort_dict_with_priority_key(_commands, &"priority")
	return _commands.duplicate() # get_commands() erases consumed keys from what it gets
