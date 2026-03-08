extends EditorConsoleSingleton.ConsoleCommandBase

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const BUILD = "build"
const GET_DIR = "get-dir"
const SET_DIR = "set-dir"

const _HELP_DICT = {
	"namespace":{
		"m":"Namespace generator plugin, available commands:",
		"c":[BUILD, GET_DIR, SET_DIR]
		},
	BUILD: "generate current namespace files",
	GET_DIR: "display the directory the files will be generated in",
	SET_DIR: "set the directory the files will be generated in -- <path String>"
}

func _get_valid_commands_for_index(completion_context:CompletionContext, cmd_idx:int) -> Dictionary:
	var commands = completion_context.commands
	var command = commands[cmd_idx]
	var commands_obj = Commands.new()
	match command:
		"namespace":
			commands_obj.add_command(BUILD, false, NamespaceBuilder.build_files)
			commands_obj.add_command(GET_DIR, false, NamespaceBuilder.get_generated_dir)
			commands_obj.add_command(SET_DIR, true, NamespaceBuilder.set_generated_dir)
			
	return commands_obj.get_commands()


func _command_requires_arguments(selected_command:String):
	if selected_command == SET_DIR:
		return true
	return false

func _get_help_dict():
	return _HELP_DICT
