@tool
extends EditorPlugin

const CheckInstance = preload("uid://cnx1roduh82r") #! resolve Singletons.CheckInstance

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const NamespaceConfig = preload("res://addons/namespace/src/namespace_config.gd")

#const ConsoleCommand = preload("res://addons/namespace/_export_ignore/plugins/console_command/console_command.gd")
#
#const DeclarationCodeCompletion = preload("res://addons/namespace/_export_ignore/plugins/declaration_code_completion.gd")
#const SyntaxHighlighting = preload("res://addons/namespace/_export_ignore/plugins/syntax_highlighting.gd")

const ConsoleCommandPath = "res://addons/namespace/_export_ignore/plugins/console_command/console_command.gd"
const DeclarationCodeCompletionPath = "res://addons/namespace/_export_ignore/plugins/declaration_code_completion.gd"
const SyntaxHighlightingPath = "res://addons/namespace/_export_ignore/plugins/syntax_highlighting.gd"

const PLUGIN_NAME = "Namespace"

var syntax_highlighting_script
var declaration_code_completion

## Everything the highlighter and code completion need, rebuilt only when it can
## actually have changed: plugin start, after a build, and on "namespace config".
## Lives here rather than in a static var because statics get wiped when an
## unrelated script reloads, while this node survives.
var namespace_classes := {}
var output_dirs := []

func _get_plugin_name() -> String:
	return PLUGIN_NAME


## Walks the editor tree for self plugin node. EditorPlugins are direct
## children of EditorNode, so this is two shallow loops rather than a recursive
## scan. Matched on plugin name instead of script identity because the export
## step can change this script's resource_path.
static func get_instance() -> EditorPlugin:
	var main_loop = Engine.get_main_loop()
	if main_loop is not SceneTree:
		return null
	var root = main_loop.root
	if root == null:
		return null
	for node in root.get_children():
		if node.get_class() != "EditorNode":
			continue
		for child in node.get_children():
			if child.get_class() != "EditorPlugin":
				continue
			if child.has_method("_get_plugin_name") and child._get_plugin_name() == PLUGIN_NAME:
				return child
		break
	return null


func refresh_cache() -> void:
	var config = NamespaceConfig.load_all(NamespaceBuilder.get_generated_dir())
	output_dirs = config.get("output_dirs", [])
	namespace_classes = NamespaceBuilder.build_namespace_classes(output_dirs)


func is_in_namespace_dir(path:String) -> bool:
	for dir in output_dirs:
		if path.begins_with(dir):
			return true
	return false

func _enable_plugin() -> void:
	#NamespaceBuilder.set_generated_dir_default()
	#SyntaxHighlighting.set_default_settings()
	pass

func _disable_plugin() -> void:
	
	pass

func _enter_tree() -> void:
	_setup.call_deferred()

func _setup():
	NamespaceBuilder.set_generated_dir_default()
	
	var sp_ins = _get_syntax_plus()
	if is_instance_valid(sp_ins):
		syntax_highlighting_script = _get_script_instance(SyntaxHighlightingPath)
		if is_instance_valid(syntax_highlighting_script):
			syntax_highlighting_script.set_default_settings()
			syntax_highlighting_script.set_colors()
			sp_ins.register_node(self)
			sp_ins.call_on_ready(_register_syntax_data)
	
	
	var ed_console = _get_editor_console()
	if is_instance_valid(ed_console):
		var console_cmd = _get_script_instance(ConsoleCommandPath)
		if is_instance_valid(console_cmd):
			ed_console.register_node(self)
			ed_console.register_temp_scope("namespace", console_cmd)
	
	
	var code_comp = _get_code_completion()
	if is_instance_valid(code_comp):
		var dec_code_comp_script = _get_script_instance(DeclarationCodeCompletionPath)
		if is_instance_valid(dec_code_comp_script):
			code_comp.register_node(self)
			declaration_code_completion = dec_code_comp_script.new()
			declaration_code_completion.plugin = self
	
	# Needs to be deferred, if this func isn't then refresh_cache.deferred()
	refresh_cache()

func _exit_tree() -> void:
	var ed_console = _get_editor_console()
	if is_instance_valid(ed_console):
		ed_console.remove_temp_scope("namespace")
		ed_console.unregister_node(self)
	
	#_unregister_syntax_data()
	var sp_ins = _get_syntax_plus()
	if is_instance_valid(sp_ins):
		sp_ins.unregister_highlight_callable("#!", "namespace")
		sp_ins.unregister_node(self)
	
	if is_instance_valid(declaration_code_completion):
		declaration_code_completion.clean_up()
	
	var code_comp = _get_code_completion()
	if is_instance_valid(code_comp):
		code_comp.unregister_node(self)


func _register_syntax_data():
	# Bound so the highlighter reaches the cache without a static var of its own.
	var sp_ins = _get_syntax_plus()
	sp_ins.register_highlight_callable("#!", "namespace", syntax_highlighting_script.get_namespace_hl_info.bind(self))
#
#func _unregister_syntax_data():
	#SyntaxPlusSingleton.unregister_highlight_callable("#!", "namespace")

func _get_script_instance(path:String):
	if FileAccess.file_exists(path):
		return load(path)
	return null

func _get_syntax_plus():
	return CheckInstance.get_instance("SyntaxPlusSingleton")

func _get_editor_console():
	return CheckInstance.get_instance("EditorConsoleSingleton")

func _get_code_completion():
	return CheckInstance.get_instance("EditorCodeCompletionSingleton")
