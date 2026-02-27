@tool
extends EditorPlugin

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

const ConsoleCommand = preload("res://addons/namespace/src/plugins/console_command.gd")

const DeclarationCodeCompletion = preload("res://addons/namespace/src/plugins/declaration_code_completion.gd")
const SyntaxHighlighting = preload("res://addons/namespace/src/plugins/syntax_highlighting.gd")

var declaration_code_completion

func _get_plugin_name() -> String:
	return "Namespace"

func _enable_plugin() -> void:
	NamespaceBuilder.set_generated_dir_default()
	SyntaxHighlighting.set_default_settings()

func _disable_plugin() -> void:
	
	pass

func _enter_tree() -> void:
	EditorConsoleSingleton.register_node(self)
	EditorConsoleSingleton.register_temp_scope("namespace", ConsoleCommand.new())
	
	EditorCodeCompletion.register_plugin(self)
	
	declaration_code_completion = DeclarationCodeCompletion.new()
	SyntaxHighlighting.set_colors()
	
	SyntaxPlusSingleton.register_node(self)
	SyntaxPlusSingleton.call_on_ready(_register_syntax_data)

func _exit_tree() -> void:
	EditorConsoleSingleton.remove_temp_scope("namespace")
	EditorConsoleSingleton.unregister_node(self)
	
	_unregister_syntax_data()
	SyntaxPlusSingleton.unregister_node(self)
	
	if is_instance_valid(declaration_code_completion):
		declaration_code_completion.clean_up()
	
	EditorCodeCompletion.unregister_plugin(self)


func _register_syntax_data():
	SyntaxPlusSingleton.register_highlight_callable("#!", "namespace", SyntaxHighlighting.get_namespace_hl_info)

func _unregister_syntax_data():
	SyntaxPlusSingleton.unregister_highlight_callable("#!", "namespace")
