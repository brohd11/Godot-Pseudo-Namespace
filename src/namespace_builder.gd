@tool
class_name NamespaceBuilder
extends EditorScript
#! remote
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_file.gd")
const URegex = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_regex.gd")
const ConfirmationDialogHandler = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/dialog/confirmation/confirmation_dialog_handler.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")


const _RES = "res://" 
const GEN_DIR_PROJECT_SETTING = "plugin/namespace/directory"

const GENERATED_DIR = "res://namespace_classes/" #! ignore-remote
const NAMESPACE_TAG = "#! namespace "

static var _open_scripts

static func parse(commands, args, editor_console):
	if commands.size() == 1:
		return
	var c_2 = commands[1]
	if c_2 == "build":
		build_files()
		return
	elif c_2 == "dir":
		print(get_generated_dir())
		return
	elif c_2 == "set-dir":
		if not args.size() == 1:
			printerr("Expected 1 arg for set-dir command.")
			return
		set_generated_dir(args[0])


static func get_completion(raw_text, commands, args, editor_console):
	var complete_data = {}
	if commands.size() == 1:
		complete_data["build"] = {}
		complete_data["dir"] = {}
		complete_data["set-dir"] = {"METADATA_KEY": {"add_args":true}}
	
	#print('%s, %s, %s, %s' % [raw_text, commands, args, editor_console])
	return complete_data


static func _get_setting_singleton(): ## Editor Settings for now. Possibly need to use ProjectSettings.save()
	return ProjectSettings
	#return EditorInterface.get_editor_settings()

static func set_generated_dir_default():
	if _get_setting_singleton().has_setting(GEN_DIR_PROJECT_SETTING):
		return
	_get_setting_singleton().set_setting(GEN_DIR_PROJECT_SETTING, GENERATED_DIR)
	if _get_setting_singleton() == ProjectSettings:
		ProjectSettings.save()

static func set_generated_dir(new_dir:String):
	if not new_dir.begins_with(_RES):
		new_dir = _RES.path_join(new_dir)
		print("Making path absolute: %s" % new_dir)
	
	_get_setting_singleton().set_setting(GEN_DIR_PROJECT_SETTING, new_dir)
	if _get_setting_singleton() == ProjectSettings:
		ProjectSettings.save()

static func get_generated_dir():
	var generated_dir = GENERATED_DIR
	var settings = _get_setting_singleton()
	if settings.has_setting(GEN_DIR_PROJECT_SETTING):
		generated_dir = settings.get_setting(GEN_DIR_PROJECT_SETTING)
	return generated_dir

func _run() -> void:
	build_files()

static func build_files():
	var generated_dir = GENERATED_DIR
	var settings = _get_setting_singleton()
	if not settings.has_setting(GEN_DIR_PROJECT_SETTING):
		settings.set_setting(GEN_DIR_PROJECT_SETTING, GENERATED_DIR)
	
	generated_dir = settings.get_setting(GEN_DIR_PROJECT_SETTING)
	var conf = ConfirmationDialogHandler.new("Ensure all files are saved before running build.")
	var handled = await conf.handled
	if not handled:
		return
	
	print("Starting namespace file generation...")
	var namespace_references = _get_used_namespace_references()
	
	var namespace_data = _scan_and_parse_namespaces()
	if namespace_data is bool:
		print("Aborting, fix namespace collisions.")
		return
	
	if namespace_data.is_empty():
		_clear_directory(generated_dir)
		_clean_up_uids(generated_dir)
		EditorInterface.get_resource_filesystem().scan()
		print("No namespace tags found. Nothing to generate.")
		return
	
	var valid = await _compare_namespace_data(namespace_references, namespace_data)
	if not valid:
		print("Aborting namespace generation.")
		return
	
	_clear_directory(generated_dir)
	
	#_generate_namespace_files(namespace_data, generated_dir)
	_generate_namespace_file_with_dir(namespace_data, generated_dir)
	
	print("Namespace file generation complete.")
	_clean_up_uids(generated_dir)
	EditorInterface.get_resource_filesystem().scan()


static func _get_used_namespace_references():
	var namespace_dir = get_generated_dir()
	var namespace_references = {}
	var namespace_classes = get_namespace_classes()
	if namespace_classes.is_empty():
		return namespace_references
	
	var class_names_pattern = "|".join(namespace_classes.keys())
	var pattern = "\\b((?:" + class_names_pattern + ")(?:\\.\\w+)*)\\b"
	var _namespace_regex = RegEx.new()
	_namespace_regex.compile(pattern)
	
	var string_regex = URegex.get_strings()
	
	var files = UFile.scan_for_files(_RES, ["gd"])
	for file_path in files:
		if file_path.begins_with(namespace_dir):
			continue
		var file_access = FileAccess.open(file_path, FileAccess.READ)
		var file_path_data = {}
		var count = 1
		while not file_access.eof_reached():
			var line = file_access.get_line()
			var anon = func(_line):
				var _matches = _namespace_regex.search_all(_line)
				for _match in _matches:
					if line.begins_with("#! namespace"):
						continue
					file_path_data[_match.get_string()] = count
				return _line
			
			URegex.string_safe_regex_read(line, anon, string_regex)
			count += 1
		
		if not file_path_data.is_empty():
			namespace_references[file_path] = file_path_data
	
	return namespace_references

static func _compare_namespace_data(namespace_references, namespace_data):
	var scripts_dict = {}
	
	for path in namespace_references.keys():
		var ref_data = namespace_references[path]
		for ref:String in ref_data.keys():
			var parts = ref.split(".", false)
			var new_data = namespace_data
			var valid_ref = true
			for part in parts:
				if new_data is not Dictionary: # trying to go too deep
					var final_path = new_data
					if not _check_script_for_member(final_path, scripts_dict, part):
						valid_ref = false
					break
				if new_data.has(part):
					new_data = new_data[part]
				else:
					valid_ref = false
					break
			if valid_ref:
				ref_data.erase(ref)
		
		if ref_data.is_empty():
			namespace_references.erase(path)
		else:
			namespace_references[path] = ref_data
	
	
	if not namespace_references.is_empty():
		print_rich("[color=fedd66]Possible broken namespace references:[/color]")
		
		for path in namespace_references.keys():
			var data = namespace_references.get(path)
			print_rich("[color=fe786b]%s[/color]" % path)
			for ref in data.keys():
				print("\tReference at line %s: %s" % [data.get(ref), ref])
		
		
		var conf = ConfirmationDialogHandler.new("Some references will be broken by\nnew namespace generated.\nProceed?")
		var handled = await conf.handled
		if not handled:
			return false
	
	return true

static func _check_script_for_member(script_path:String, scripts_dict:Dictionary, member_to_check:String):
	if member_to_check == "new":
		return true # this doesnt appear in members
	
	if not scripts_dict.has(script_path):
		var script = load(script_path)
		var script_data = {}
		var s_members = UClassDetail.script_get_all_members(script)
		script_data["script"] = s_members
		var c_members = UClassDetail.class_get_all_members(script)
		script_data["class"] = c_members
		scripts_dict[script_path] = script_data
	
	var script_data = scripts_dict[script_path]
	var s_members = script_data.get("script", [])
	if member_to_check in s_members:
		return true
	var c_members = script_data.get("class", [])
	if member_to_check in c_members:
		return true
	
	return false


static func _get_open_scripts(): # TODO MOVE this somewhere handy?
	var open_scripts = EditorInterface.get_script_editor().get_open_scripts()
	var open_scripts_dict = {}
	for script in open_scripts:
		var path = script.resource_path
		open_scripts_dict[path] = script
	
	return open_scripts_dict

static func _get_all_files(namespace_data, file_array, first_level=true):
	for key in namespace_data.keys():
		var value = namespace_data.get(key)
		if value is Dictionary:
			_get_all_files(value, file_array, true)
		elif value is String:
			file_array.append(value)


static func _clear_directory(directory: String):
	var dir_arrays = UFile.scan_for_dirs(directory, true)
	for array in dir_arrays:
		array.reverse()
		for dir in array:
			var dir_access = DirAccess.open(dir)
			var files = dir_access.get_files()
			for f in files:
				if f.get_extension() == "uid":
					continue
				var file_path = dir.path_join(f)
				DirAccess.remove_absolute(file_path)
	
	if not DirAccess.dir_exists_absolute(directory):
		return
	var dir_access = DirAccess.open(directory)
	var files = dir_access.get_files()
	for file in files:
		if file.get_extension() == "uid":
			continue
		var file_path = directory.path_join(file)
		DirAccess.remove_absolute(file_path)
	
	
	#UFile.recursive_delete_in_dir(directory)
	
	## DELETE ONLY TOP LEVEL
	#var dir = DirAccess.open(directory)
	#if not dir:
		#print("Generated directory does not exist, creating it: ", directory)
		#DirAccess.make_dir_recursive_absolute(directory)
		#return
#
	#for file_name in dir.get_files():
		#if file_name.ends_with(".gd"):
			#var err = dir.remove(file_name)
			#if err != OK:
				#printerr("Failed to remove old file: ", directory.path_join(file_name))


static func _clean_up_uids(directory: String):
	var dir_arrays = UFile.scan_for_dirs(directory, true)
	for array in dir_arrays:
		array.reverse()
		for dir in array:
			var dir_access = DirAccess.open(dir)
			var files = dir_access.get_files()
			for f in files:
				if f.get_extension() != "uid":
					continue
				var file_path = dir.path_join(f)
				if FileAccess.file_exists(file_path.get_basename()):
					continue
				DirAccess.remove_absolute(file_path)
			
			files = dir_access.get_files()
			if files.is_empty():
				DirAccess.remove_absolute(dir)
		
	var dir_access = DirAccess.open(directory)
	var files = dir_access.get_files()
	for file in files:
		if file.get_extension() != "uid":
			continue
		var file_path = directory.path_join(file)
		if FileAccess.file_exists(file_path.get_basename()):
			continue
		DirAccess.remove_absolute(file_path)
	
	#var gd_files = UFile.scan_for_files(directory, ["gd"])
	#for path in gd_files:
		#var file_access = FileAccess.open(path, FileAccess.READ)
		#while not 


static func _scan_and_parse_namespaces() -> Variant:
	var lines_to_check = 10
	var data = {}
	var all_files = UFile.scan_for_files(_RES, ["gd"])
	var open_scripts = EditorInterface.get_script_editor().get_open_scripts()
	var open_scripts_dict = {}
	for script in open_scripts:
		var path = script.resource_path
		open_scripts_dict[path] = script
	var open_script_paths = open_scripts_dict.keys()
	for file_path in all_files:
		
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			printerr("Could not open file: ", file_path)
			continue
		
		for i in range(lines_to_check):
			var line = file.get_line()
			if line.begins_with(NAMESPACE_TAG):
				var namespace_string = line.trim_prefix(NAMESPACE_TAG).strip_edges()
				if not namespace_string.is_empty():
					var success = _add_to_namespace_data(data, line, file_path)
					#var success = _add_to_namespace_data(data, namespace_string, file_path)
					if not success:
						return false
				break
		
		file.close()
	
	return data


#region MULTI FILE NAMESPACE

# Main entry point. Iterates through the top-level keys in the data.
static func _generate_namespace_file_with_dir(data: Dictionary, generated_dir: String):
	DirAccess.make_dir_recursive_absolute(generated_dir)
	for top_level_class_name in data.keys():
		var sub_data = data[top_level_class_name]
		_generate_class_and_subclasses(top_level_class_name, sub_data, generated_dir, generated_dir)


static func _generate_class_and_subclasses(_class_name: String, data: Dictionary, parent_dir_path: String, generated_dir):
	var file_name = _class_name.to_snake_case() + ".gd"
	var file_path = parent_dir_path.path_join(file_name)
	
	var child_dir_path = parent_dir_path.path_join(_class_name.to_snake_case())
	
	var file_content = "# This file is auto-generated. Do not edit.\n\n"
	if parent_dir_path == generated_dir:
		file_content += "class_name %s\n\n" % _class_name # "" <- parser
	
	var sorted_keys = data.keys()
	sorted_keys.sort()
	
	var has_subclasses = false
	
	for key in sorted_keys:
		var value = data[key]
		
		if value is Dictionary: # This will be a nested class in its own file
			has_subclasses = true
			var sub_class_file_name = key.to_snake_case() + ".gd"
			var sub_class_path = child_dir_path.path_join(sub_class_file_name)
			
			# Build UID for proper path population on first run.
			var uid_path = sub_class_path + ".uid"
			if not FileAccess.file_exists(uid_path):
				if not DirAccess.dir_exists_absolute(uid_path.get_base_dir()):
					DirAccess.make_dir_recursive_absolute(uid_path.get_base_dir())
				var uid_file = FileAccess.open(uid_path, FileAccess.WRITE)
				var new_uid = ResourceUID.create_id()
				var new_uid_string = ResourceUID.id_to_text(new_uid)
				uid_file.store_string(new_uid_string)
				ResourceUID.add_id(new_uid, sub_class_path)
			
			
			file_content += _get_preload(key, sub_class_path)
			
		elif value is String: # This is a final constant (e.g., a scene path)
			file_content += _get_preload(key, value)
	
	if FileAccess.file_exists(file_path):
		var trimmed_path = file_path.trim_prefix(generated_dir).trim_prefix("/")
		var message = "Namespace collision, ensure consistent case style as file names are converted to snake_case: %s | %s"
		printerr(message % [_class_name, trimmed_path])
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(file_content)
		file.close()
	else:
		printerr("Failed to write to file: ", file_path)
		return # Stop if we can't write the parent file
	
	var uid_path = file_path + ".uid"
	if not FileAccess.file_exists(uid_path):
		var uid_file = FileAccess.open(uid_path, FileAccess.WRITE)
		var new_uid = ResourceUID.create_id()
		var new_uid_string = ResourceUID.id_to_text(new_uid)
		uid_file.store_string(new_uid_string)
		
		ResourceUID.add_id(new_uid, file_path)
	
	# subclasses, create their directory and recurse
	if has_subclasses:
		DirAccess.make_dir_recursive_absolute(child_dir_path)
		for key in sorted_keys:
			var value = data[key]
			if value is Dictionary:
				_generate_class_and_subclasses(key, value, child_dir_path, generated_dir)
#endregion


#region SINGLE FILE NAMESPACE

static func _generate_namespace_files(data: Dictionary, generated_dir):
	for top_level_namespace in data.keys():
		var file_content = "# This file is auto-generated. Do not edit.\n\n"
		file_content += "class_name %s\n\n" % top_level_namespace
		
		var sub_data = data[top_level_namespace]
		file_content += _generate_class_content(sub_data, 0)
		
		var file_name = top_level_namespace.to_snake_case() + ".gd"
		var target_path = generated_dir.path_join(file_name)
		
		var file = FileAccess.open(target_path, FileAccess.WRITE)
		if file:
			file.store_string(file_content)
			file.close()
		else:
			printerr("Failed to write to file: ", target_path)


static func _generate_class_content(data: Dictionary, indent_level: int) -> String:
	var content = ""
	var indent = ""
	for i in range(indent_level):
		indent += "\t"
	
	var sorted_keys = data.keys()
	sorted_keys.sort()
	
	for key in sorted_keys:
		var value = data[key]
		if value is Dictionary: # It's a nested class
			content += indent + "class %s:\n" % key # "" <- parser
			content += _generate_class_content(value, indent_level + 1)
		elif value is String: # It's a final constant
			content += indent + _get_preload(key, value)
	
	return content

#endregion

static func _add_to_namespace_data(data: Dictionary, current_line_text: String, file_path: String):
	#var parts = namespace_string.split(".")
	var parts = get_namespace_string_parts(current_line_text)
	
	var current_level = data
	
	for i in range(parts.size()):
		var part = parts[i]
		if not part.is_valid_ascii_identifier():
			print("Invalid identifier: %s" % part)
			return false
		if i == parts.size() - 1: # This is the last part (the class name)
			if current_level.has(part):
				printerr("Namespace collision! '%s' already exists. Overwriting." % current_line_text)
			current_level[part] = file_path
		else: # This is a namespace or inner class
			if not current_level.has(part):
				current_level[part] = {}
			elif not current_level[part] is Dictionary:
				printerr("Namespace conflict! '%s' is defined as both a class and a namespace." % part)
				return false # Abort this entry
			current_level = current_level[part]
	return true


static func _get_preload(name, path):
	var uid = UFile.path_to_uid(path)
	return 'const %s = preload("%s") # %s\n' % [name, uid, path] # "" <- parser

static func get_namespace_string_parts(original_line_text:String, clean_parts:=true):
	
	var stripped_text = original_line_text.trim_prefix("#! namespace").strip_edges() # "" <- parser
	
	var namespace_string = stripped_text
	var class_idx = stripped_text.find(" class") # "" <- parser
	if class_idx > -1:
		namespace_string = stripped_text.get_slice(" class", 0).strip_edges() # "" <- parser
	
	var parts = namespace_string.split(".", false)
	
	if class_idx > -1:
		var class_string = stripped_text.get_slice(" class", 1).strip_edges() # "" <- parser
		if class_string != "":
			parts.append(class_string)
	
	if clean_parts:
		for i in range(parts.size()):
			var part = parts[i]
			if part.find(" ") > -1:
				part = part.get_slice(" ", 0)
				parts[i] = part
	
	return parts


static func get_namespace_classes() -> Dictionary:
	var namespace_dir = NamespaceBuilder.GENERATED_DIR
	var settings = _get_setting_singleton()
	if settings.has_setting(NamespaceBuilder.GEN_DIR_PROJECT_SETTING):
		namespace_dir = settings.get_setting(NamespaceBuilder.GEN_DIR_PROJECT_SETTING)
	
	var namespace_files = []
	if DirAccess.dir_exists_absolute(namespace_dir):
		var files = DirAccess.get_files_at(namespace_dir)
		for f in files:
			var path = namespace_dir.path_join(f)
			namespace_files.append(path)
	
	var syntax_plus_ins = SyntaxPlus.get_instance()
	var valid_global_classes = {}
	var class_data = ProjectSettings.get_global_class_list()
	for dict in class_data:
		var path = dict.get("path")
		if path in namespace_files:
			var name = dict.get("class")
			valid_global_classes[name] = path
	
	return valid_global_classes

static func class_name_in_script(word, script):
	var const_map = script.get_script_constant_map()
	if const_map.has(word):
		return const_map.get(word)
