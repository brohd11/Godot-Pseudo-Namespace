@tool
extends EditorPlugin

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const NamespaceConfig = preload("res://addons/namespace/src/namespace_config.gd")

const ConsoleCommand = preload("res://addons/namespace/src/plugins/console_command/console_command.gd")

const DeclarationCodeCompletion = preload("res://addons/namespace/src/plugins/declaration_code_completion.gd")
const SyntaxHighlighting = preload("res://addons/namespace/src/plugins/syntax_highlighting.gd")

const PLUGIN_NAME = "Namespace"

var declaration_code_completion

## Everything the highlighter and code completion need, rebuilt only when it can
## actually have changed: plugin start, after a build, and on "namespace config".
## Lives here rather than in a static var because statics get wiped when an
## unrelated script reloads, while this node survives.
var namespace_classes := {}
var output_dirs := []

func _get_plugin_name() -> String:
	return PLUGIN_NAME


## Walks the editor tree for our own plugin node. EditorPlugins are direct
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
	NamespaceBuilder.set_generated_dir_default()
	SyntaxHighlighting.set_default_settings()
	
	EditorConsoleSingleton.register_node(self)
	EditorConsoleSingleton.register_temp_scope("namespace", ConsoleCommand)
	
	EditorCodeCompletion.register_plugin(self)
	
	declaration_code_completion = DeclarationCodeCompletion.new()
	declaration_code_completion.plugin = self
	SyntaxHighlighting.set_colors()

	SyntaxPlusSingleton.register_node(self)
	SyntaxPlusSingleton.call_on_ready(_register_syntax_data)

	# Deferred: the editor is still starting up here.
	refresh_cache.call_deferred()

func _exit_tree() -> void:
	EditorConsoleSingleton.remove_temp_scope("namespace")
	EditorConsoleSingleton.unregister_node(self)
	
	_unregister_syntax_data()
	SyntaxPlusSingleton.unregister_node(self)
	
	if is_instance_valid(declaration_code_completion):
		declaration_code_completion.clean_up()
	
	EditorCodeCompletion.unregister_plugin(self)


func _register_syntax_data():
	# Bound so the highlighter reaches the cache without a static var of its own.
	SyntaxPlusSingleton.register_highlight_callable("#!", "namespace", SyntaxHighlighting.get_namespace_hl_info.bind(self))

func _unregister_syntax_data():
	SyntaxPlusSingleton.unregister_highlight_callable("#!", "namespace")
