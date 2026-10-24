extends SceneTree
## Builds namespace files without the editor, exiting 0 on success and 1 on abort.
##     godot --headless --path . --script res://addons/namespace/run_headless.gd [-- <flags>]
## Prompts that would delete or break something abort unless their flag is given.
## A newly generated root class_name registers on the editor's next scan (or --import).

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const FLAG_DELETE_ORPHANS = "--delete-orphans"
const FLAG_ALLOW_BROKEN = "--allow-broken"

const _USAGE = \
"Usage: run_headless.gd [-- --delete-orphans --allow-broken]
  --delete-orphans  delete generated files no namespace config claims anymore
  --allow-broken    build even if existing references would break"

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	for arg in args:
		if arg not in [FLAG_DELETE_ORPHANS, FLAG_ALLOW_BROKEN]:
			printerr("Unknown argument: %s" % arg)
			print(_USAGE)
			quit(1)
			return

	NamespaceBuilder.set_generated_dir_default()
	var answers = {
		NamespaceBuilder.Prompt.SAVE_FILES: true, # no editor, so nothing unsaved
		NamespaceBuilder.Prompt.DELETE_ORPHANS: FLAG_DELETE_ORPHANS in args,
		NamespaceBuilder.Prompt.BROKEN_REFS: FLAG_ALLOW_BROKEN in args,
	}
	var success = await NamespaceBuilder.build_files(answers)
	if not success:
		printerr("Namespace build aborted. If the above is expected, rerun with the matching flag.")
		print(_USAGE)
	quit(0 if success else 1)
