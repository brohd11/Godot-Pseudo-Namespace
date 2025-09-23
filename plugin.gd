@tool
extends EditorPlugin

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const CodeCompletion = preload("res://addons/namespace/src/code_completion.gd")
const SyntaxHighlighting = preload("res://addons/namespace/src/syntax_highlighting.gd")

var editor_console:EditorConsole

func _get_plugin_name() -> String:
	return "Namespace"
#func _get_plugin_icon() -> Texture2D:
	#return EditorInterface.get_base_control().get_theme_icon("Node", &"EditorIcons")
#func _has_main_screen() -> bool:
	#return true

func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	editor_console = EditorConsole.register_plugin(self)
	
	var scope_data = {
		"namespace": {"script":NamespaceBuilder}
	}
	editor_console.register_temp_scope(scope_data)
	
	CodeCompletion.connect_signal()
	
	SyntaxPlus.call_on_ready(_register_syntax_data)

func _exit_tree() -> void:
	if is_instance_valid(editor_console):
		editor_console.remove_temp_scope("namespace")
		editor_console.unregister_node(self)
	
	CodeCompletion.disconnect_signal()
	
	_unregister_syntax_data()

func _register_syntax_data():
	SyntaxPlus.register_highlight_callable("namespace", SyntaxHighlighting.get_namespace_hl_info)

func _unregister_syntax_data():
	SyntaxPlus.unregister_highlight_callable("namespace")
