extends EditorCodeCompletion


#! import-g NamespaceBuilder,EditorPluginManager,
#! import-p UClassDetail,UString,

const _IMPORT_SHOW_GLOBAL = "import-show-global"
const _IMPORT_PRELOADS = "import-preloads"
const _IMPORT_P = "import-p"
const _IMPORT_G = "import-g"

const IMPORT_MEMBERS_CURRENT = &"import_members_current"
const IMPORT_MEMBERS = &"import_members"
const IMPORTED_CLASSES = &"imported_classes"
const NAMESPACE_PATHS = &"namespace_paths"
const OPTIONS_TO_SKIP = &"options_to_skip"
const CALL_WITH_ARGS = "(\u2026)"

 
var editor_theme:Theme
var data_cache:Dictionary = {}

var global_paths = {}
var preload_paths = {}

var imported_classes:Dictionary = {}
var imported_class_names:Array = []
var hide_global_classes = false
var hide_private_members = false


const _COMMENT_TAGS = {
	"#!": {
		_IMPORT_SHOW_GLOBAL:null,
		_IMPORT_PRELOADS:null,
		_IMPORT_P:"_import_syntax_hl",
		_IMPORT_G:"_import_syntax_hl",
	}
}


func _singleton_ready():
	for prefix in _COMMENT_TAGS.keys():
		var tag_data = _COMMENT_TAGS.get(prefix)
		for tag in tag_data.keys():
			var callable_nm = tag_data.get(tag)
			if callable_nm == null:
				SyntaxPlus.register_comment_tag(prefix, tag)
			else:
				var callable = get(callable_nm)
				SyntaxPlus.register_highlight_callable(prefix, tag, callable, SyntaxPlus.CallableLocation.START)
			register_tag(prefix, tag, TagLocation.START)


func _on_editor_script_changed(script):
	editor_theme = EditorInterface.get_editor_theme()
	_get_script_imports()
	_get_global_and_preloads()


func _on_code_completion_requested(script_editor:CodeEdit) -> bool:
	hide_private_members = true #^r create editor setting?
	data_cache.clear() # TEST
	#^g test area ^^
	
	
	if is_index_in_comment():
		var caret_line = script_editor.get_caret_line()
		var current_line_text = script_editor.get_line(caret_line)
		var import_hint_options = _import_hint_autocomplete(current_line_text)
		if not import_hint_options.is_empty():
			add_completion_options(import_hint_options)
			return true
		return false
	var word_before_cursor = get_word_before_cursor()
	if word_before_cursor.find(".") > -1:
		return false
	
	var existing_options = script_editor.get_code_completion_options()
	if existing_options.is_empty(): # TEST # need to use this somehow
		if _SKIP_KEYWORDS.has(word_before_cursor):
			return false
	
	var t2 = ALibRuntime.Utils.UProfile.TimeFunction.new("get data")
	
	var options = []
	var options_dict:Dictionary = {}
	var current_script = EditorInterface.get_script_editor().get_current_script()
	var cache_cc_options = _get_cached_data(IMPORT_MEMBERS_CURRENT, current_script.resource_path, data_cache)
	if cache_cc_options == null:
		cache_cc_options = _get_code_complete_options()
		_store_data(IMPORT_MEMBERS_CURRENT, current_script.resource_path, cache_cc_options, current_script, data_cache)
	
	var cc_options = cache_cc_options.duplicate(true)
	t2.stop()
	
	var options_to_skip = cc_options.get(OPTIONS_TO_SKIP, {})
	cc_options.erase(OPTIONS_TO_SKIP)
	
	var hide_private = get_hide_private_members_setting()
	
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("sort dict")
	for e in existing_options:
		var display = e.display_text
		if options_to_skip.has(display):
			continue
		if hide_private:
			if display.begins_with("_"):
				continue
		if hide_global_classes:
			if global_paths.has(display):
				continue
		
		options_dict[display] = e
	
	t.stop()
	
	options_dict.merge(cc_options)
	options = options_dict.values()
	var t3 = ALibRuntime.Utils.UProfile.TimeFunction.new("ADDING")
	add_completion_options(options, false)
	t3.stop()
	return true


func _get_code_complete_options():
	var cc_options = {}
	var options_to_skip = {}
	
	#var current_script = EditorInterface.get_script_editor().get_current_script() #^ should be ok to skip this
	#var current_script_members = _get_script_member_code_complete_options(current_script, "", options_to_skip)
	#cc_options.merge(current_script_members)
	
	for access_path in imported_classes.keys():
		var script = imported_classes.get(access_path)
		var members = _get_script_member_code_complete_options(script, access_path, options_to_skip, ["const", "enum", "method"])
		cc_options.merge(members)
	
	cc_options[OPTIONS_TO_SKIP] = options_to_skip
	return cc_options


func _get_script_member_code_complete_options(script:GDScript, access_name:String, 
				options_to_skip:Dictionary, member_hints:=UClassDetail._MEMBER_ARGS):
	
	var cache_key = script.resource_path if script.resource_path != "" else script
	var cc_options = _get_cached_data(IMPORT_MEMBERS, script.resource_path, data_cache)
	if cc_options == null:
		cc_options = {}
		
		cc_options[access_name] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS,access_name, access_name, "Object")
		options_to_skip[access_name] = true
		
		for hint in member_hints:
			var options:Dictionary
			if hint == "enum":
				options = _get_enum_options(script, access_name)
			elif hint ==  "const":
				options = _get_const_options(script, access_name)
			elif hint == "property":
				options = _get_property_options(script, access_name)
			elif hint == "signal":
				options = _get_signal_options(script, access_name)
			elif hint == "method":
				options = _get_method_options(script, access_name, true)
			
			if options != null:
				if options.has(OPTIONS_TO_SKIP):
					options_to_skip.merge(options[OPTIONS_TO_SKIP])
					options.erase(OPTIONS_TO_SKIP)
				cc_options.merge(options)
		
		_store_data(IMPORT_MEMBERS, cache_key, cc_options, script, data_cache)
	
	
	return cc_options


func _get_property_options(script:GDScript, access_name:String):
	var properties = UClassDetail.script_get_all_properties(script)#, true)
	var cc_options = {}
	for p in properties:
		if p.ends_with(".gd"):
			continue
		if hide_private_members and p.begins_with("_"):
			continue
		var data = properties.get(p)
		
		#var flags = data.get("flags")
		#if not (flags & METHOD_FLAG_STATIC):
			#continue
		#print(data)
		var cc_nm = access_name + "." + p if access_name != "" else p
		cc_options[cc_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_MEMBER,cc_nm,cc_nm,"property")
	return cc_options
	

func _get_const_options(script:GDScript, access_name:String):
	var options_to_skip = {}
	var constants = UClassDetail.script_get_all_constants(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var cc_options = {}
	for c in constants:
		if hide_private_members and c.begins_with("_"):
			continue
		#continue
		var icon = "const"
		var val = constants.get(c)
		if val is GDScript:
			if imported_classes.has(c):
				continue
			if preload_paths.has(val.resource_path):
				continue
			icon = "Object"
		
		var cc_nm = access_name + "." + c if access_name != "" else c
		cc_options[cc_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CONSTANT,cc_nm,cc_nm,icon)
		
		if val is GDScript:# and val.resource_path == "":
			var nested_options = _get_script_member_code_complete_options(val, cc_nm, options_to_skip, ["const", "method", "enum"])
			if nested_options.has(OPTIONS_TO_SKIP):
				options_to_skip.merge(nested_options[OPTIONS_TO_SKIP])
				nested_options.erase(OPTIONS_TO_SKIP)
			cc_options.merge(nested_options)
	
	
	cc_options[OPTIONS_TO_SKIP] = options_to_skip
	return cc_options


func _get_method_options(script:GDScript, access_name:String, include_new:bool=false):
	var methods = UClassDetail.script_get_all_methods(script, UClassDetail.IncludeInheritance.SCRIPTS_ONLY)
	var cc_options = {}
	var init_args:Array
	
	for m in methods:
		var data = methods.get(m)
		var name = data.get("name")
		if include_new:
			if name == "_init":
				init_args = data.get("args")
				continue
		
		if hide_private_members and m.begins_with("_"):
			continue
		
		var flags = data.get("flags")
		if not (flags & METHOD_FLAG_STATIC):
			continue
		var args = data.get("args")
		var cc_nm = access_name + "." + m if access_name != "" else m
		var cc_ins = cc_nm + "("
		if args.is_empty():
			cc_nm = cc_nm + "()"
			cc_ins = cc_nm
		else:
			cc_nm = cc_nm + CALL_WITH_ARGS
		cc_options[cc_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_FUNCTION,cc_nm,cc_ins,"method")
	
	if include_new and access_name != "":
		var has_args = false
		if not init_args.is_empty():
			has_args = true
		var new_call = access_name + ".new()"
		var new_call_ins = new_call
		if has_args:
			new_call = access_name + ".new" + CALL_WITH_ARGS
			new_call_ins = access_name + ".new("
		cc_options[new_call] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_FUNCTION,new_call,new_call_ins,"constructor")
	
	return cc_options


func _get_signal_options(script:GDScript, access_name:String):
	var signals = UClassDetail.script_get_all_signals(script)
	var cc_options = {}
	for s in signals:
		if hide_private_members and s.begins_with("_"):
			continue
		var cc_nm = access_name + "." + s if access_name != "" else s
		cc_options[cc_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_SIGNAL,cc_nm,cc_nm,"signal")
	return cc_options

func _get_enum_options(script:GDScript, access_name:String):
	var enums = UClassDetail.script_get_all_enums(script)#, true)
	var cc_options = {}
	for e in enums:
		if hide_private_members and e.begins_with("_"):
			continue
		var cc_nm = access_name + "." + e if access_name != "" else e
		cc_options[cc_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_ENUM,cc_nm,cc_nm,"enum")
		
		var enum_members = enums.get(e)
		for em in enum_members.keys():
			var em_nm = cc_nm + "." + em
			cc_options[em_nm] = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_ENUM,em_nm,em_nm,"enum")
	
	return cc_options

func _get_code_complete_dict(kind:CodeEdit.CodeCompletionKind, display_text, insert_text, icon_name, default_value=null, font_color:Color=Color.LIGHT_GRAY):
	var icon
	if icon_name == "constructor":
		icon = editor_theme.get_icon("MemberConstructor", "EditorIcons")
	elif icon_name == "const":
		icon = editor_theme.get_icon("MemberConstant", "EditorIcons")
	elif icon_name == "property":
		icon = editor_theme.get_icon("MemberProperty", "EditorIcons")
	elif icon_name == "signal":
		icon = editor_theme.get_icon("MemberSignal", "EditorIcons")
	elif icon_name == "method":
		icon = editor_theme.get_icon("MemberMethod", "EditorIcons")
	elif icon_name == "enum":
		icon = editor_theme.get_icon("Enum", "EditorIcons")
	else:
		icon = editor_theme.get_icon(icon_name, "EditorIcons")
	return {
		"kind":kind,
		"display_text":display_text,
		"insert_text":insert_text,
		"font_color":font_color,
		"icon":icon,
		"default_value":default_value
	}
	


func _get_script_imports():
	var t = ALibRuntime.Utils.UProfile.TimeFunction.new("get hints")
	var script_editor = get_code_edit()
	if script_editor == null:
		return []
	var import_hints = {
		_IMPORT_SHOW_GLOBAL: false,
		_IMPORT_PRELOADS: false,
		_IMPORT_P: {},
		_IMPORT_G: {},
	}
	var line_count = script_editor.get_line_count()
	for i in range(10):
		if not i < line_count:
			break
		var line = script_editor.get_line(i)
		if not line.begins_with("#! import"):
			continue
		var hint = line.get_slice("#!", 1).strip_edges().get_slice(" ", 0).strip_edges()
		if hint == _IMPORT_SHOW_GLOBAL:
			import_hints[_IMPORT_SHOW_GLOBAL] = true
		elif hint == _IMPORT_PRELOADS:
			import_hints[_IMPORT_PRELOADS] = true
		elif hint.begins_with(_IMPORT_P):
			var current_classes = _get_current_classes_in_hint(line, _IMPORT_P)
			for _class in current_classes:
				import_hints[_IMPORT_P][_class] = true
		elif hint.begins_with(_IMPORT_G):
			var current_classes = _get_current_classes_in_hint(line, _IMPORT_G)
			for _class in current_classes:
				import_hints[_IMPORT_G][_class] = true
	
	imported_classes.clear()
	var deep = false
	var include_inner = true
	var current_script = get_current_script()
	var preloads = UClassDetail.script_get_preloads(current_script, deep, include_inner)
	if import_hints[_IMPORT_PRELOADS] == true:
		for _class in preloads.keys():
			var pl_script = preloads[_class]
			imported_classes[_class] = pl_script
	else:
		for _class in import_hints[_IMPORT_P].keys():
			var pl_script = preloads.get(_class)
			if pl_script != null:
				imported_classes[_class] = pl_script
	
	for _class in import_hints[_IMPORT_G].keys():
		var path = UClassDetail.get_global_class_path(_class)
		if path != "":
			var g_script = load(path)
			imported_classes[_class] = g_script
	
	if import_hints[_IMPORT_SHOW_GLOBAL] == true:
		hide_global_classes = false
	else:
		hide_global_classes = true
	
	imported_class_names = imported_classes.keys()
	t.stop()


func _get_global_and_preloads():
	global_paths = UClassDetail.get_all_global_class_paths()
	
	preload_paths.clear()
	var preloads = UClassDetail.script_get_preloads(get_current_script())
	for _name in preloads:
		var script = preloads.get(_name)
		if script.resource_path != "":
			preload_paths[script.resource_path] = true


func _import_syntax_hl(current_line_text:String, line:int, comment_tag_idx:int):
	var substr = current_line_text.substr(comment_tag_idx + 2).strip_edges()
	var hint = substr.get_slice(" ", 0).strip_edges()
	var global_hint = hint == _IMPORT_G
	var preload_hint = hint == _IMPORT_P
	if not (global_hint or preload_hint):
		return {}
	
	var editor_settings = EditorInterface.get_editor_settings()
	var global_class_color = editor_settings.get_setting("text_editor/theme/highlighting/user_type_color")
	var preload_class_color = editor_settings.get_setting("text_editor/theme/highlighting/gdscript/global_function_color")
	var comment_color = SyntaxPlus.get_instance().comment_color
	var symbol_color = SyntaxPlus.get_instance().symbol_color
	
	var default_tag_color = SyntaxPlus.get_instance().DEFAULT_TAG_COLOR
	
	var current_classes = _get_current_classes_in_hint(current_line_text, hint)
	var hl_info = {}
	hl_info[0] = SyntaxPlus.get_hl_info_dict(default_tag_color)
	hl_info[hint.length() + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
	
	var in_scope_class_names:Array
	var class_color:Color
	
	if global_hint:
		var global_classes = UClassDetail.get_all_global_class_paths()
		in_scope_class_names = global_classes.keys()
		class_color = global_class_color
	elif preload_hint:
		var current_script = get_current_script()
		var preloads = UClassDetail.script_get_preloads(current_script, true)
		in_scope_class_names = preloads.keys()
		class_color = preload_class_color
	
	for _class_name in current_classes:
		if _class_name in in_scope_class_names:
			var idx = substr.find(_class_name)
			hl_info[idx] = SyntaxPlus.get_hl_info_dict(class_color)
			var comma_idx = substr.find(",", idx)
			if comma_idx != -1:
				hl_info[comma_idx] = SyntaxPlus.get_hl_info_dict(symbol_color)
				hl_info[comma_idx + 1] = SyntaxPlus.get_hl_info_dict(comment_color)
	
	return hl_info


func _get_current_classes_in_hint(current_line_text:String, slice_str:String):
	var current_classes_str = current_line_text.get_slice(slice_str, 1).strip_edges()
	var current_classes = current_classes_str.split(",",false)
	for i in range(current_classes.size()):
		var nm = current_classes[i]
		nm = nm.strip_edges()
		current_classes[i] = nm
	return current_classes

func _import_hint_autocomplete(current_line_text:String):
	var options = []
	var full_g_hint = "#! " + _IMPORT_G
	var full_p_hint = "#! " + _IMPORT_P
	if current_line_text.begins_with(full_g_hint):
		var current_classes = _get_current_classes_in_hint(current_line_text, full_g_hint)
		global_paths = UClassDetail.get_all_global_class_paths()
		var class_names = global_paths.keys()
		for _name in class_names:
			if _name in current_classes:
				continue
			var completion = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
		
	elif current_line_text.begins_with(full_p_hint):
		var current_classes = _get_current_classes_in_hint(current_line_text, full_p_hint)
		var current_script = get_current_script()
		var preloads = UClassDetail.script_get_preloads(current_script, true)
		for _name in preloads.keys():
			if _name.find(".") > -1:
				continue
			if _name in current_classes:
				continue
			var completion = _get_code_complete_dict(CodeEdit.CodeCompletionKind.KIND_CLASS, _name, _name + ",", "Object")
			options.append(completion)
	
	return options

const _SKIP_KEYWORDS = {
	"pass":true,
	"return":true,
	}
