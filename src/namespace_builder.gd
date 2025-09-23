@tool
class_name NamespaceBuilder
extends EditorScript
#! remote
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_file.gd")

const _RES = "res://" 
const GEN_DIR_PROJECT_SETTING = "plugin/namespace/directory"

const GENERATED_DIR = "res://namespace_classes/" #! ignore-remote
const NAMESPACE_TAG = "#! namespace "

static func parse(commands, args, editor_console:EditorConsole):
	print(commands)
	if commands.size() == 1:
		return
	var c_2 = commands[1]
	if c_2 == "build":
		build_files()
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
		complete_data["set-dir"] = {"METADATA_KEY": {"add_args":true}}
	#print('%s, %s, %s, %s' % [raw_text, commands, args, editor_console])
	return complete_data

static func set_generated_dir(new_dir:String):
	if not new_dir.begins_with(_RES):
		new_dir = _RES.path_join(new_dir)
		print("Making path absolute: %s" % new_dir)
	
	ProjectSettings.set_setting(GEN_DIR_PROJECT_SETTING, new_dir)


func _run() -> void:
	build_files()

static func build_files():
	var generated_dir = GENERATED_DIR
	if not ProjectSettings.has_setting(GEN_DIR_PROJECT_SETTING):
		ProjectSettings.set_setting(GEN_DIR_PROJECT_SETTING, GENERATED_DIR)
	
	generated_dir = ProjectSettings.get_setting(GEN_DIR_PROJECT_SETTING)
	
	print("Starting namespace file generation...")
	
	_clear_directory(generated_dir)
	
	var namespace_data = _scan_and_parse_namespaces()
	if namespace_data.is_empty():
		print("No namespace tags found. Nothing to generate.")
		return
	
	_generate_namespace_files(namespace_data, generated_dir)
	
	print("Namespace file generation complete.")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


static func _clear_directory(path: String):
	var dir = DirAccess.open(path)
	if not dir:
		print("Generated directory does not exist, creating it: ", path)
		DirAccess.make_dir_recursive_absolute(path)
		return

	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			var err = dir.remove(file_name)
			if err != OK:
				printerr("Failed to remove old file: ", path.path_join(file_name))


static func _scan_and_parse_namespaces() -> Dictionary:
	var data = {}
	var all_files = UFile.scan_for_files(_RES, ["gd"])
	
	for file_path in all_files:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			printerr("Could not open file: ", file_path)
			continue
		
		var count = 0
		while not file.eof_reached() and count < 10:
			var line = file.get_line()
			if line.begins_with(NAMESPACE_TAG):
				var namespace_string = line.trim_prefix(NAMESPACE_TAG).strip_edges()
				if not namespace_string.is_empty():
					_add_to_namespace_data(data, namespace_string, file_path)
				break
			count += 1
		
		file.close()
		
	return data


static func _generate_namespace_files(data: Dictionary, generated_dir):
	for top_level_namespace in data.keys():
		var file_content = "# This file is auto-generated. Do not edit.\n\n"
		file_content += "class_name %s\n\n" % top_level_namespace
		
		var sub_data = data[top_level_namespace]
		# Start recursive generation with an indent level of 1.
		file_content += _generate_class_content(sub_data, 0)
		
		var file_name = top_level_namespace.to_snake_case() + ".gd"
		var target_path = generated_dir.path_join(file_name)
		
		var file = FileAccess.open(target_path, FileAccess.WRITE)
		if file:
			file.store_string(file_content)
			file.close()
		else:
			printerr("Failed to write to file: ", target_path)


static func _add_to_namespace_data(data: Dictionary, namespace_string: String, file_path: String):
	var parts = namespace_string.split(".")
	var current_level = data

	for i in range(parts.size()):
		var part = parts[i]
		if not part.is_valid_ascii_identifier():
			print("Invalid identifier: %s" % part)
			return
		if i == parts.size() - 1: # This is the last part (the class name)
			if current_level.has(part):
				printerr("Namespace collision! '%s' already exists. Overwriting." % namespace_string)
			current_level[part] = file_path
		else: # This is a namespace or inner class
			if not current_level.has(part):
				current_level[part] = {}
			elif not current_level[part] is Dictionary:
				printerr("Namespace conflict! '%s' is defined as both a class and a namespace." % part)
				return # Abort this entry
			current_level = current_level[part]


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
			content += indent + 'const %s = preload("%s")\n' % [key, value] # "" <- parser
	
	return content


static func get_namespace_classes():
	var namespace_dir = NamespaceBuilder.GENERATED_DIR
	
	if ProjectSettings.has_setting(NamespaceBuilder.GEN_DIR_PROJECT_SETTING):
		namespace_dir = ProjectSettings.get_setting(NamespaceBuilder.GEN_DIR_PROJECT_SETTING)
	
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
