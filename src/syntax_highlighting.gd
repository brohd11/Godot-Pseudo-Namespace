
static func get_namespace_hl_info(current_line_text):
	var syntax_plus_ins = SyntaxPlus.get_instance()
	var namespace_files = NamespaceBuilder.get_namespace_classes()
	var namespace_dir = NamespaceBuilder.get_generated_dir()
	
	var stripped_text:String = current_line_text.get_slice("#!", 1).replace(".", " ").strip_edges()
	var new_hl_info = syntax_plus_ins.get_single_line_highlight(stripped_text)
	var words = stripped_text.split(" ")
	words.remove_at(0) 
	if words.size() < 1: 
		return new_hl_info
	var namespace_class = words[0]
	if not namespace_files.has(namespace_class):
		return new_hl_info
	
	var ns_idx = stripped_text.find(namespace_class)
	new_hl_info[ns_idx] = {"color": Color.SKY_BLUE}
	words.remove_at(0)
	
	var namespace_script = load(namespace_files.get(namespace_class))
	if namespace_script == null:
		return new_hl_info
	
	var last_idx = current_line_text.find("namespace") + "namespace".length()
	for i in range(words.size()):
		var word = words[i]
		if namespace_script:
			namespace_script = syntax_plus_ins.class_name_in_script(word, namespace_script)
		
		var idx = stripped_text.find(word, last_idx)
		last_idx = idx + word.length() - 1
		#print(namespace_script.resource_path)
		if namespace_script != null:
			#var idx = stripped_text.find(word, last_idx)
			#last_idx = idx
			if namespace_script.resource_path.begins_with(namespace_dir): # existing namespace member
				_set_hl_info_at_idx(new_hl_info, idx, Color.SKY_BLUE)
				#new_hl_info[idx] = {"color": Color.SKY_BLUE}
			else:
				var current_script = EditorInterface.get_script_editor().get_current_script().resource_path
				if current_script == namespace_script.resource_path:
					_set_hl_info_at_idx(new_hl_info, idx, Color.DARK_CYAN)
					#new_hl_info[idx] = {"color": Color.DARK_CYAN} # current script generated
				else:
					_set_hl_info_at_idx(new_hl_info, idx, Color.FIREBRICK)
					#new_hl_info[idx] = {"color": Color.FIREBRICK} # overwriting
			new_hl_info[idx + word.length()] = {"color": syntax_plus_ins.symbol_color}
			
		else:
			_set_hl_info_at_idx(new_hl_info, idx, Color.GREEN)
			#new_hl_info[idx] = {"color": Color.GREEN} # new class
			new_hl_info[idx + word.length()] = {"color": syntax_plus_ins.symbol_color}
	
	return new_hl_info

static func _set_hl_info_at_idx(hl_info, idx, color):
	var color_data = hl_info.get(idx)
	if color_data:
		var existing_color = color_data.get("color")
		if existing_color != SyntaxPlus.default_text_color:
			hl_info[idx] = {"color": Color.RED}
			return
	
	hl_info[idx] = {"color":color}
	
	
