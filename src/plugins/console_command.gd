extends EditorConsoleSingleton.ConsoleCommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

func get_commands() -> Dictionary:
	var commands_obj = Commands.new()
	commands_obj.add_command("build", false, NamespaceBuilder.build_files)
	commands_obj.add_command("get-dir", false, NamespaceBuilder.get_generated_dir)
	commands_obj.add_command("set-dir", true, NamespaceBuilder.set_generated_dir)
	return commands_obj.get_commands()

func get_completion(_raw_text, commands, _args):
	if commands.size() == 1:
		return get_commands()
