
const PLUGIN_SETTING = "plugin/namespace/"
const COLOR_BUILT_IN_CLASH = PLUGIN_SETTING + "color/built_in_clash"
const COLOR_EXISTING = PLUGIN_SETTING + "color/existing"
const COLOR_CURRENT = PLUGIN_SETTING + "color/current"
const COLOR_CLASH = PLUGIN_SETTING + "color/clash"
const COLOR_NEW = PLUGIN_SETTING + "color/new"

const _default_settings = {
	COLOR_BUILT_IN_CLASH: Color(0.919, 0.0, 0.0),
	COLOR_EXISTING: Color(0.267, 0.586, 0.706),
	COLOR_CURRENT: Color(0.626, 0.848, 0.943),
	COLOR_CLASH: Color(0.596, 0.098, 0.098),
	COLOR_NEW: Color(0.378, 0.715, 0.322)
}

static var color_built_in_clash
static var color_existing
static var color_current
static var color_clash
static var color_new

static func set_default_settings():
	var ed_set = EditorInterface.get_editor_settings()
	for setting in _default_settings.keys():
		if not ed_set.has_setting(setting):
			ed_set.set_setting(setting, _default_settings.get(setting))

static func set_colors():
	var ed_set = EditorInterface.get_editor_settings()
	color_built_in_clash = ed_set.get_setting(COLOR_BUILT_IN_CLASH)
	color_existing = ed_set.get_setting(COLOR_EXISTING)
	color_current = ed_set.get_setting(COLOR_CURRENT)
	color_clash = ed_set.get_setting(COLOR_CLASH)
	color_new = ed_set.get_setting(COLOR_NEW)
	
	if not ed_set.settings_changed.is_connected(_on_editor_settings_changed):
		ed_set.settings_changed.connect(_on_editor_settings_changed)

static func _on_editor_settings_changed():
	set_colors()

static func get_namespace_hl_info(current_line_text):
	#var syntax_plus_ins = SyntaxPlus.get_instance() # THINK CAN BE ELIMINATED, CHECK THAT IS INSTANCED BY PLUGIN
	var namespace_files = NamespaceBuilder.get_namespace_classes()
	var namespace_dir = NamespaceBuilder.get_generated_dir()
	
	var stripped_text:String = current_line_text.get_slice("#!", 1).replace(".", " ").strip_edges()
	var new_hl_info = SyntaxPlus.get_single_line_highlight(stripped_text)
	#var words = stripped_text.split(" ")
	#words.remove_at(0) # remove namespace
	var words = NamespaceBuilder.get_namespace_string_parts(current_line_text)
	if words.size() < 1: 
		return new_hl_info
	var namespace_class = words[0]
	
	if not namespace_files.has(namespace_class):
		return _new_namespace_highlighting(current_line_text, new_hl_info, words)
	
	var ns_idx = stripped_text.find(namespace_class)
	_set_hl_info_at_idx(new_hl_info, ns_idx, namespace_class, color_existing, true)
	words.remove_at(0)
	
	var namespace_script = load(namespace_files.get(namespace_class))
	if namespace_script == null:
		return new_hl_info
	
	var last_idx = ns_idx + namespace_class.length()
	for i in range(words.size()):
		var word = words[i]
		if namespace_script:
			namespace_script = NamespaceBuilder.class_name_in_script(word, namespace_script)
		
		var idx = stripped_text.find(word, last_idx)
		if idx == -1:
			if word.find(".") > -1:
				var first_part = word.get_slice(".", 0)
				var first_idx = stripped_text.find(first_part, last_idx)
				_set_hl_info_at_idx(new_hl_info, first_idx, word, color_clash)
				for key in new_hl_info.keys():
					if key > first_idx:
						new_hl_info.erase(key)
				return new_hl_info
		
		last_idx = idx + word.length() - 1
		
		if namespace_script != null:
			if namespace_script.resource_path.begins_with(namespace_dir) and i < words.size() - 1: # existing namespace member
				_set_hl_info_at_idx(new_hl_info, idx, word, color_existing)
			else:
				var current_script = EditorInterface.get_script_editor().get_current_script().resource_path
				if current_script == namespace_script.resource_path:
					_set_hl_info_at_idx(new_hl_info, idx, word, color_current) # current script generated
				else:
					_set_hl_info_at_idx(new_hl_info, idx, word, color_clash) # overwriting
			
		else:
			_set_hl_info_at_idx(new_hl_info, idx, word, color_new) # new class
	
	return new_hl_info

static func _new_namespace_highlighting(current_line_text:String, hl_info:Dictionary, words:Array):
	var stripped_text:String = current_line_text.get_slice("#!", 1).replace(".", " ").strip_edges()
	var last_idx = stripped_text.find("namespace") + "namespace".length()
	for word:String in words:
		var idx = stripped_text.find(word, last_idx)
		last_idx = idx + word.length() - 1
		_set_hl_info_at_idx(hl_info, idx, word, color_new)
	return hl_info

static func _set_hl_info_at_idx(hl_info, idx, word, color, force:=false):
	var symbol_color = SyntaxPlus.get_instance().symbol_color
	hl_info[idx + word.length()] = {"color": symbol_color}
	var color_data = hl_info.get(idx)
	if color_data and not force:
		var existing_color = color_data.get("color")
		if existing_color != SyntaxPlus.get_instance().default_text_color:
			hl_info[idx] = {"color": color_built_in_clash}
			return
	
	hl_info[idx] = {"color":color}
	
