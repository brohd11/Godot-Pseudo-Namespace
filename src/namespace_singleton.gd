extends "res://addons/_lib/singleton/src/singleton_base.gd" #! ext Singletons.Base
## Editor-side cache for the namespace builder and the hidden plugins. Holds data
## only; NamespaceBuilder.refresh_cache() fills it. Created by plugin.gd, so a CLI
## or bare EditorScript run never has one and the builder reads from disk instead.

const CheckInstance = preload("uid://cnx1roduh82r") #! resolve Singletons.CheckInstance
## Re-exported for the hidden plugins: they ship verbatim, so their own preloads
## must stay inside this plugin while this one gets rewritten on export.
const RuntimeExtend = preload("uid://d222tctvfbhp2") #! resolve Singletons.RuntimeExtend

const PE_STRIP_CAST_SCRIPT = preload("res://addons/namespace/src/namespace_singleton.gd")

static func get_singleton_name() -> String:
	return "NamespaceSingleton"

static func get_instance() -> PE_STRIP_CAST_SCRIPT:
	return _get_instance(PE_STRIP_CAST_SCRIPT)

static func instance_valid() -> bool:
	return _instance_valid(PE_STRIP_CAST_SCRIPT)

static func call_on_ready(callable, print_err:bool=true):
	_call_on_ready(PE_STRIP_CAST_SCRIPT, callable, print_err)


## Everything the highlighter and code completion need, rebuilt only when it can
## actually have changed: plugin start, after a build, and on "namespace config".
## Lives on this node rather than in a static var because statics get wiped when
## an unrelated script reloads, while the node survives.
var namespace_classes := {}
var output_dirs := []

func is_in_namespace_dir(path:String) -> bool:
	for dir in output_dirs:
		if path.begins_with(dir):
			return true
	return false


static func get_syntax_plus():
	return CheckInstance.get_instance("SyntaxPlusSingleton")

static func get_editor_console():
	return CheckInstance.get_instance("EditorConsoleSingleton")

static func get_code_completion():
	return CheckInstance.get_instance("EditorCodeCompletionSingleton")
