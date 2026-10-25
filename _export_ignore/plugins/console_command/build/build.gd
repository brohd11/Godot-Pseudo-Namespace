extends EditorConsoleSingleton.CommandBase #! pe-runtime-extend

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const _HELP = \
"Generate namespace files for current tags
Usage: namespace build (optional: --no-dialog --delete-orphans --allow-broken)"

var no_dialog_flag := false
var delete_orphans_flag := false
var allow_broken_flag := false

static func get_command_name() -> String:
	return "build"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 0
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--no-dialog", {
		&"help": "Never open a dialog. Unflagged destructive prompts abort instead, as in run_headless.gd."
	})
	options.add_option("--delete-orphans", {
		&"help": "Delete generated files no namespace config claims anymore, without asking."
	})
	options.add_option("--allow-broken", {
		&"help": "Build even if existing references would break, without asking."
	})
	return options.get_options()


func _execute(ctx:Context):
	# A missing key opens that dialog, so without --no_dialog flags only preset a yes.
	var answers = {}
	if no_dialog_flag:
		answers[NamespaceBuilder.Prompt.SAVE_FILES] = true
	if no_dialog_flag or delete_orphans_flag:
		answers[NamespaceBuilder.Prompt.DELETE_ORPHANS] = delete_orphans_flag
	if no_dialog_flag or allow_broken_flag:
		answers[NamespaceBuilder.Prompt.BROKEN_REFS] = allow_broken_flag

	# Holds the console until any remaining confirm dialogs are answered.
	var success = await NamespaceBuilder.build_files(answers)
	if not success:
		ctx.append_error("Namespace build aborted, see the output log.")
		return ExitCode.FAIL
	return ExitCode.OK
