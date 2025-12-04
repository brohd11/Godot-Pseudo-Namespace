@tool
extends EditorPlugin

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const DeclarationCodeCompletion = preload("res://addons/namespace/src/declaration_code_completion.gd")
const SyntaxHighlighting = preload("res://addons/namespace/src/syntax_highlighting.gd")

var declaration_code_completion
var editor_console:EditorConsole
var syntax_plus:SyntaxPlus


func _get_plugin_name() -> String:
	return "Namespace"

func _enable_plugin() -> void:
	NamespaceBuilder.set_generated_dir_default()
	SyntaxHighlighting.set_default_settings()

func _disable_plugin() -> void:
	
	pass

func _enter_tree() -> void:
	editor_console = EditorConsole.register_plugin(self)
	
	var scope_data = {
		"namespace": {"script":NamespaceBuilder}
	}
	editor_console.register_temp_scope(scope_data)
	
	EditorCodeCompletion.register_plugin(self)
	
	declaration_code_completion = DeclarationCodeCompletion.new()
	SyntaxHighlighting.set_colors()
	
	syntax_plus = SyntaxPlus.register_node(self)
	SyntaxPlus.call_on_ready(_register_syntax_data)

func _exit_tree() -> void:
	if is_instance_valid(editor_console):
		editor_console.remove_temp_scope("namespace")
		editor_console.unregister_node(self)
	
	if is_instance_valid(syntax_plus):
		_unregister_syntax_data()
		syntax_plus.unregister_node(self)
	
	if is_instance_valid(declaration_code_completion):
		declaration_code_completion.clean_up()
	
	EditorCodeCompletion.unregister_plugin(self)


func _register_syntax_data():
	SyntaxPlus.register_highlight_callable("#!", "namespace", SyntaxHighlighting.get_namespace_hl_info)

func _unregister_syntax_data():
	SyntaxPlus.unregister_highlight_callable("#!", "namespace")
