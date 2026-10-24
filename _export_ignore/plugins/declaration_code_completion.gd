extends EditorCodeCompletion

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")

## Set by plugin.gd right after this is constructed. Holds the namespace cache,
## so completion never has to look the plugin up while the user is typing.
var plugin

func _singleton_ready():
	singleton.register_tag("#!", "namespace", EditorCodeCompletionSingleton.TagLocation.START)

func _on_editor_script_changed(script):
	pass

func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	var caret_context = get_caret_context()
	if caret_context.is_in_function_call():
		return false
	
	var current_line_text = script_editor.get_line(script_editor.get_caret_line())
	if current_line_text.begins_with("#! namespace"):
		return _namespace_declaration(script_editor, current_line_text)
	#elif current_line_text.find("extends ") > -1: # "" <- parser
		#if script_editor.get_caret_column() < current_line_text.find("extends "): # "" <- parser
			#return false
		#return _get_extended_class(script_editor, current_line_text)
	elif current_line_text.find("=") > -1:
		var eq_idx = current_line_text.find("=")
		if eq_idx == -1 or script_editor.get_caret_column() < eq_idx: # "" <- parser
			return false
		return _assignment(script_editor, current_line_text)
	return false


#region Declaration/Assignment

func _namespace_declaration(text_ed:CodeEdit, current_line_text:String):
	var namespace_classes = plugin.namespace_classes
	var icon = _get_icon("Script")
	var words = NamespaceBuilder.get_namespace_string_parts(current_line_text)
	if words.size() < 2:
		if words.is_empty() or not namespace_classes.has(words[0]) and current_line_text.find(".") == -1:
			for _class in namespace_classes.keys():
				text_ed.add_code_completion_option(CodeEdit.KIND_CONSTANT, _class, _class, Color.GRAY, icon)
			
			text_ed.update_code_completion_options(false)
			return true
	
	return _get_namespace_code_completions(text_ed, current_line_text, true)


func _get_extended_class(text_ed:CodeEdit, current_line_text:String):
	var stripped_text:String = current_line_text.get_slice("extends ", 1).strip_edges() # "" <- parser
	return _get_namespace_code_completions(text_ed, stripped_text)

func _assignment(text_ed:CodeEdit, current_line_text:String):
	var stripped_text:String = current_line_text.get_slice("=", 1).strip_edges() # "" <- parser
	return _get_namespace_code_completions(text_ed, stripped_text)


func _get_namespace_code_completions(text_ed, current_line_text, show_scripts = true):
	var words = NamespaceBuilder.get_namespace_string_parts(current_line_text, false)
	if words.size() == 0:
		return false
	
	var first_word = words[0]
	words.remove_at(0)
	var namespace_classes = plugin.namespace_classes
	if not namespace_classes.has(first_word):
		return false
	
	var namespace_path = namespace_classes.get(first_word)
	var had_valid = _check_scripts(text_ed, namespace_path, words, show_scripts)
	if had_valid:
		text_ed.cancel_code_completion()
		text_ed.update_code_completion_options(false)
		return true
	return false

func _check_scripts(text_ed:CodeEdit, namespace_path:String, words:Array, show_external:=false):
	var namespace_script:Script = load(namespace_path)
	if not namespace_script:
		return false
	
	var idx = 0
	var current_script: Script = namespace_script
	for word in words:
		var next_script = NamespaceBuilder.class_name_in_script(word, current_script)
		idx += 1
		if next_script and next_script is GDScript:
			if not show_external and not plugin.is_in_namespace_dir(next_script.resource_path):
				break # if not showing external, don't list options from external
			
			current_script = next_script
		else:
			var forbidden = [" ", "."]
			for f in forbidden:
				if f in word:
					return
			break
	if idx < words.size() - 1:
		return
	
	var constants = current_script.get_script_constant_map()
	if not plugin.is_in_namespace_dir(current_script.resource_path):
		return false # if current script is outside, don't want to overide completions
	
	var added_options = []
	var icon
	for key in constants.keys():
		var script = constants.get(key)
		if script is not Script:
			continue
		
		var script_path = script.resource_path
		if not plugin.is_in_namespace_dir(script_path):
			if not show_external:
				continue
			else:
				icon = _get_icon("Script")
		else:
			icon = _get_icon("Object")
		
		added_options.append(key)
		text_ed.add_code_completion_option(CodeEdit.KIND_CLASS, key, key, Color.GRAY, icon)
	
	if added_options.is_empty():
		return false
	return true

static func _get_icon(icon_name, theme=&"EditorIcons"):
	return EditorInterface.get_base_control().get_theme_icon(icon_name, theme)

#endregion
