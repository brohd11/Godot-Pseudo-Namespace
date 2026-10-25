@tool
extends EditorPlugin

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
const NamespaceSingleton = preload("res://addons/namespace/src/namespace_singleton.gd")

#const ConsoleCommand = preload("res://addons/namespace/_export_ignore/plugins/console_command/console_command.gd")
#
#const DeclarationCodeCompletion = preload("res://addons/namespace/_export_ignore/plugins/declaration_code_completion.gd")
#const SyntaxHighlighting = preload("res://addons/namespace/_export_ignore/plugins/syntax_highlighting.gd")

const ConsoleCommandPath = "res://addons/namespace/_export_ignore/plugins/console_command/console_command.gd"
const DeclarationCodeCompletionPath = "res://addons/namespace/_export_ignore/plugins/declaration_code_completion.gd"
const SyntaxHighlightingPath = "res://addons/namespace/_export_ignore/plugins/syntax_highlighting.gd"

const PLUGIN_NAME = "Namespace"

var syntax_highlighting
var console_command_script
var declaration_code_completion

func _get_plugin_name() -> String:
	return PLUGIN_NAME


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
	# Before any hidden plugin is instanced, they fetch it in their _init.
	NamespaceSingleton.get_instance()
	
	var sp_ins = NamespaceSingleton.get_syntax_plus()
	if is_instance_valid(sp_ins):
		var syntax_highlighting_script = _get_script_instance(SyntaxHighlightingPath)
		if is_instance_valid(syntax_highlighting_script):
			syntax_highlighting_script.set_default_settings()
			syntax_highlighting_script.set_colors()
			# Held here: the registered callable alone would not keep it alive.
			syntax_highlighting = syntax_highlighting_script.new()
			sp_ins.register_node(self)
			sp_ins.call_on_ready(_register_syntax_data)
	
	
	var ed_console = NamespaceSingleton.get_editor_console()
	if is_instance_valid(ed_console):
		# Held here: outside the resource cache, so nothing else keeps it or its subcommands alive.
		console_command_script = NamespaceSingleton.RuntimeExtend.build_from_singleton(ConsoleCommandPath, "EditorConsoleSingleton", "CommandBase")
		if is_instance_valid(console_command_script):
			ed_console.register_node(self)
			ed_console.register_temp_scope("namespace", console_command_script)
	
	
	var code_comp = NamespaceSingleton.get_code_completion()
	if is_instance_valid(code_comp):
		var dec_code_comp_script = NamespaceSingleton.RuntimeExtend.build_from_singleton(DeclarationCodeCompletionPath, "EditorCodeCompletionSingleton", "EditorCodeCompletion")
		if is_instance_valid(dec_code_comp_script):
			code_comp.register_node(self)
			declaration_code_completion = dec_code_comp_script.new()
	
	# Needs to be deferred, if this func isn't then refresh_cache.deferred()
	NamespaceBuilder.refresh_cache()

func _exit_tree() -> void:
	var ed_console = NamespaceSingleton.get_editor_console()
	if is_instance_valid(ed_console):
		ed_console.remove_temp_scope("namespace")
		ed_console.unregister_node(self)
	
	#_unregister_syntax_data()
	var sp_ins = NamespaceSingleton.get_syntax_plus()
	if is_instance_valid(sp_ins):
		sp_ins.unregister_highlight_callable("#!", "namespace")
		sp_ins.unregister_node(self)
	
	if is_instance_valid(declaration_code_completion):
		declaration_code_completion.clean_up()
	
	var code_comp = NamespaceSingleton.get_code_completion()
	if is_instance_valid(code_comp):
		code_comp.unregister_node(self)
	
	# A leftover cache would be preferred over disk by builds run after disabling.
	if NamespaceSingleton.instance_valid():
		var singleton = NamespaceSingleton.get_instance()
		# Detached now, so a re-enable within this frame creates a fresh one.
		singleton.get_parent().remove_child(singleton)
		singleton.queue_free()


func _register_syntax_data():
	var sp_ins = NamespaceSingleton.get_syntax_plus()
	sp_ins.register_highlight_callable("#!", "namespace", syntax_highlighting.get_namespace_hl_info)
#
#func _unregister_syntax_data():
	#SyntaxPlusSingleton.unregister_highlight_callable("#!", "namespace")

func _get_script_instance(path:String):
	if FileAccess.file_exists(path):
		return load(path)
	return null
