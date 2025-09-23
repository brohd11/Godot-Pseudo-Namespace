
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


static func _class_name_in_script(word, script):
	var const_map = script.get_script_constant_map()
	if const_map.has(word):
		return const_map.get(word)

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


static func _namespace_declaration(text_ed:CodeEdit, current_line_text:String):
	var namespace_classes = NamespaceBuilder.get_namespace_classes()
	var icon = _get_icon("Script")
	
	var stripped_text:String = current_line_text.get_slice("#! namespace", 1).replace(".", " ").strip_edges()
	var words = stripped_text.split(" ", false)
	if words.size() < 2:
		if words.is_empty() or not namespace_classes.has(words[0]):
			for _class in namespace_classes.keys():
				text_ed.add_code_completion_option(CodeEdit.KIND_CONSTANT, _class, _class, Color.WHITE, icon)
				
			text_ed.update_code_completion_options(false)
			return
	
	var namespace_class = words[0]
	words.remove_at(0)
	if not namespace_classes.has(namespace_class):
		return
	
	var namespace_path = namespace_classes.get(namespace_class)
	_check_scripts(text_ed, namespace_path, words)


static func _get_extended_class(text_ed:CodeEdit, current_line_text:String):
	var stripped_text:String = current_line_text.get_slice("extends ", 1).replace(".", " ").strip_edges() # "" <- parser
	var words = stripped_text.split(" ", false)
	if words.size() == 0:
		return
	
	var first_word = words[0]
	words.remove_at(0)
	var namespace_classes = NamespaceBuilder.get_namespace_classes()
	if not namespace_classes.has(first_word):
		return
	text_ed.cancel_code_completion()
	var namespace_path = namespace_classes.get(first_word)
	_check_scripts(text_ed, namespace_path, words, true)


static func _check_scripts(text_ed:CodeEdit, namespace_path:String, words:Array, show_scripts:=false):
	var namespace_script:Script = load(namespace_path)
	if not namespace_script:
		return
	
	var current_script: Script = namespace_script
	for word in words:
		var next_script = _class_name_in_script(word, current_script)
		if next_script:
			current_script = next_script
		else:
			break
	
	var constants = current_script.get_script_constant_map()
	#print("Final Script: ", current_script.resource_path)
	#print("Found Constants: ", constants.keys())
	var icon
	for key in constants.keys():
		var script = constants.get(key)
		if script is not Script:
			continue
		var script_path = script.resource_path
		if not (script_path == "" or script_path == namespace_path):
			if not show_scripts:
				continue
			else:
				icon = _get_icon("Script")
		else:
			icon = _get_icon("Object")
		
		text_ed.add_code_completion_option(CodeEdit.KIND_CLASS, key, key, Color.WHITE, icon)
	
	text_ed.update_code_completion_options(false)

static func _get_icon(icon_name, theme=&"EditorIcons"):
	return EditorInterface.get_base_control().get_theme_icon(icon_name, theme)
