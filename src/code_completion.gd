
static var last_code_edit:CodeEdit

static func connect_signal():
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_editor_script_changed)

static func disconnect_signal():
	EditorInterface.get_script_editor().editor_script_changed.disconnect(_on_editor_script_changed)

static func _on_editor_script_changed(script):
	if is_instance_valid(last_code_edit):
		if last_code_edit.code_completion_requested.is_connected(_on_code_completion_requested):
			last_code_edit.code_completion_requested.disconnect(_on_code_completion_requested)
	
	last_code_edit = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	if is_instance_valid(last_code_edit):
		if not last_code_edit.code_completion_requested.is_connected(_on_code_completion_requested):
			last_code_edit.code_completion_requested.connect(_on_code_completion_requested)


static func _on_code_completion_requested():
	var text_ed = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	await text_ed.get_tree().process_frame
	var current_line_text = text_ed.get_line(text_ed.get_caret_line())
	if current_line_text.begins_with("#! namespace"):
		_namespace_declaration(text_ed, current_line_text)
		return
	elif current_line_text.find("extends ") > -1: # "" <- parser
		if text_ed.get_caret_column() < current_line_text.find("extends "): # "" <- parser
			return
		_get_extended_class(text_ed, current_line_text)
		return
	elif current_line_text.find("=") > -1:
		var eq_idx = current_line_text.find("=")
		if eq_idx == -1 or text_ed.get_caret_column() < eq_idx: # "" <- parser
			return
		_assignment(text_ed, current_line_text)

static func _namespace_declaration(text_ed:CodeEdit, current_line_text:String):
	var namespace_classes = NamespaceBuilder.get_namespace_classes()
	var icon = _get_icon("Script")
	
	#var words = stripped_text.split(" ", false)
	var words = NamespaceBuilder.get_namespace_string_parts(current_line_text)
	
	if words.size() < 2:
		if words.is_empty() or not namespace_classes.has(words[0]) and current_line_text.find(".") == -1:
			for _class in namespace_classes.keys():
				text_ed.add_code_completion_option(CodeEdit.KIND_CONSTANT, _class, _class, Color.WHITE, icon)
			
			
			text_ed.update_code_completion_options(false)
			return
	
	_get_namespace_code_completions(text_ed, current_line_text, true)


static func _get_extended_class(text_ed:CodeEdit, current_line_text:String):
	var stripped_text:String = current_line_text.get_slice("extends ", 1).strip_edges() # "" <- parser
	
	_get_namespace_code_completions(text_ed, stripped_text)

static func _assignment(text_ed:CodeEdit, current_line_text:String):
	var stripped_text:String = current_line_text.get_slice("=", 1).strip_edges() # "" <- parser
	
	_get_namespace_code_completions(text_ed, stripped_text)

static func _get_namespace_code_completions(text_ed, current_line_text, show_scripts = true):
	var words = NamespaceBuilder.get_namespace_string_parts(current_line_text, false)
	if words.size() == 0:
		return
	
	var first_word = words[0]
	words.remove_at(0)
	var namespace_classes = NamespaceBuilder.get_namespace_classes()
	if not namespace_classes.has(first_word):
		return
	
	var namespace_path = namespace_classes.get(first_word)
	var had_valid = _check_scripts(text_ed, namespace_path, words, show_scripts)
	if had_valid:
		text_ed.cancel_code_completion()
		text_ed.update_code_completion_options(false)
	

static func _check_scripts(text_ed:CodeEdit, namespace_path:String, words:Array, show_external:=false):
	var namespace_dir = NamespaceBuilder.get_generated_dir()
	var namespace_script:Script = load(namespace_path)
	if not namespace_script:
		return false
	
	var idx = 0
	var current_script: Script = namespace_script
	for word in words:
		var next_script = NamespaceBuilder.class_name_in_script(word, current_script)
		idx += 1
		if next_script:
			if not show_external and not next_script.resource_path.begins_with(namespace_dir):
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
	if not current_script.resource_path.begins_with(namespace_dir):
		return false # if current script is outside, don't want to overide completions
	
	#print("Final Script: ", current_script.resource_path)
	#print("Found Constants: ", constants.keys())
	var added_options = []
	var icon
	for key in constants.keys():
		var script = constants.get(key)
		if script is not Script:
			continue
		
		var script_path = script.resource_path
		if not script_path.begins_with(namespace_dir):
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
