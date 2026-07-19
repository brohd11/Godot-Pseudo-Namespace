@tool
extends EditorScript
#! remote
const Dialog = preload("res://addons/addon_lib/brohd/alib_runtime/dialog/dialog.gd")
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")
const URegex = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_regex.gd")
const UClassDetail = preload("res://addons/addon_lib/brohd/alib_editor/utils/src/u_class_detail.gd")
const NamespaceConfig = preload("res://addons/namespace/src/namespace_config.gd")
const Plugin = preload("res://addons/namespace/plugin.gd") #! ignore-remote

@warning_ignore_start("static_called_on_instance")

const _RES = "res://"
const GEN_DIR_PROJECT_SETTING = "plugin/namespace/directory"

const GENERATED_DIR = "res://namespace_classes/" #! ignore-remote
const NAMESPACE_TAG = "#! namespace "

## Marks a file as owned by this tool. Deletion and class discovery both key off
## it, so it must only ever be written by _generate_class_and_subclasses.
const GENERATED_HEADER = "# This file is auto-generated. Do not edit."

#static var _open_scripts


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

	# Refused here as well as in load_all, so the console says so immediately
	# rather than at the next build.
	if NamespaceConfig.is_hidden_path(new_dir):
		printerr("Cannot generate into a hidden directory, Godot does not index those: %s" % new_dir)
		return

	_get_setting_singleton().set_setting(GEN_DIR_PROJECT_SETTING, new_dir)
	if _get_setting_singleton() == ProjectSettings:
		ProjectSettings.save()

static func get_generated_dir():
	var generated_dir = GENERATED_DIR
	var settings = _get_setting_singleton()
	if settings.has_setting(GEN_DIR_PROJECT_SETTING):
		generated_dir = settings.get_setting(GEN_DIR_PROJECT_SETTING)
	# Trailing slash matters: without it "res://ns" also prefix matches "res://ns_backup/".
	return NamespaceConfig.normalize_dir(generated_dir)


## Loads config from disk. Not cached: a build always wants fresh data, and the
## editor side keeps its own cache on the plugin instance.
static func get_config() -> Dictionary:
	return NamespaceConfig.load_all(get_generated_dir())


## Which root builds where, for diagnostics outside a build. Costs a full tag
## scan because claims are derived from where the tags live, so this is only for
## manual commands, never anything on an editor hot path.
static func resolve_claims_now(config:Dictionary={}) -> Dictionary:
	if config.is_empty():
		config = get_config()
	var root_sources = {}
	var namespace_data = _scan_and_parse_namespaces([], root_sources)
	if namespace_data is bool:
		return {"root_dirs": {}, "sources": {}, "clashes": []}
	return NamespaceConfig.resolve_claims(config.get("configs", []), root_sources)


## Every directory the build writes to, including the default. Distinct, sorted,
## each with a trailing slash. Prefers the plugin's cache; falls back to a fresh
## load so this script still works run directly as an EditorScript.
static func get_all_output_dirs() -> Array:
	var plugin = Plugin.get_instance()
	if plugin:
		return plugin.output_dirs
	return get_config().get("output_dirs", [get_generated_dir()])

## Single path convenience. Resolving the directory list costs a plugin lookup,
## so anything checking many paths should hoist get_all_output_dirs() out of its
## loop and use _path_in_dirs directly.
static func is_in_namespace_dir(path:String) -> bool:
	return _path_in_dirs(path, get_all_output_dirs())

static func _path_in_dirs(path:String, dirs:Array) -> bool:
	for dir in dirs:
		if path.begins_with(dir):
			return true
	return false

## True only for files this tool wrote. Output directories can live inside addon
## folders next to hand written scripts, so deletion must never rely on the
## extension alone.
static func _is_generated_file(path:String) -> bool:
	if path.get_extension() != "gd":
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var first_line = file.get_line()
	file.close()
	return first_line == GENERATED_HEADER

func _run() -> void:
	build_files()

static func build_files():
	var settings = _get_setting_singleton()
	if not settings.has_setting(GEN_DIR_PROJECT_SETTING):
		settings.set_setting(GEN_DIR_PROJECT_SETTING, GENERATED_DIR)

	var generated_dir = get_generated_dir()
	var confirmed = await Dialog.confirm("Ensure all files are saved before running build.")
	if not confirmed:
		return

	print("Starting namespace file generation...")

	var config = get_config()
	if not _report_config_errors(config):
		print("Aborting, fix namespace config errors.")
		return

	var namespace_references = _get_used_namespace_references(config.get("output_dirs", []))

	var generated_files = []
	var root_sources = {}
	var namespace_data = _scan_and_parse_namespaces(generated_files, root_sources)
	if namespace_data is bool:
		print("Aborting, fix namespace collisions.")
		return

	# Claims depend on where the tags live, so this can only run once they are known.
	var claims = NamespaceConfig.resolve_claims(config.get("configs", []), root_sources)
	_report_claims(config, claims, root_sources)
	
	var dir_to_roots = _map_roots_to_dirs(claims, namespace_data, generated_dir)
	var all_dirs = _get_dirs_to_clear(config, dir_to_roots, generated_dir)

	# Ahead of the empty-data return below, so removing every tag in the project
	# still reconciles output left outside the directories we account for.
	var orphans_resolved = await _confirm_orphans(generated_files, all_dirs)
	if not orphans_resolved:
		print("Aborting namespace generation.")
		return

	if namespace_data.is_empty():
		for dir in all_dirs:
			_clear_directory(dir)
		for dir in all_dirs:
			_clean_up_uids(dir)
		refresh_plugin_cache()
		EditorInterface.get_resource_filesystem().scan()
		print("No namespace tags found. Nothing to generate.")
		return

	var valid = await _compare_namespace_data(namespace_references, namespace_data)
	if not valid:
		print("Aborting namespace generation.")
		return

	# Clear every directory before generating into any of them. Two roots can
	# share an output directory, so clearing per root would wipe the first one.
	for dir in all_dirs:
		_clear_directory(dir)

	#_generate_namespace_files(namespace_data, generated_dir) #^ for inner class style
	for dir in all_dirs:
		if not dir_to_roots.has(dir):
			continue
		var roots = dir_to_roots[dir]
		roots.sort() # write order decides which side a name collision reports
		_generate_namespace_file_with_dir(namespace_data, dir, roots)

	print("Namespace file generation complete.")

	for dir in all_dirs:
		_clean_up_uids(dir)

	# Highlighting and completion query straight after a build. Refreshed before
	# the rescan on purpose: the cache is built by reading the files we just
	# wrote, so it does not have to wait for the (asynchronous) scan.
	refresh_plugin_cache()
	EditorInterface.get_resource_filesystem().scan()


## No-op when the plugin is not running, e.g. this script run as an EditorScript.
static func refresh_plugin_cache():
	var plugin = Plugin.get_instance()
	if plugin:
		plugin.refresh_cache()


## Generated files sitting outside every directory this build accounts for. They
## are output from a configuration that no longer exists: a claim removed, a
## whole [namespace] section deleted, or a config file moved to a folder that
## resolves its path elsewhere.
static func _get_orphan_files(generated_files:Array, all_dirs:Array) -> Array:
	var orphans = []
	for path in generated_files:
		if _path_in_dirs(path, all_dirs):
			continue
		orphans.append(path)
	orphans.sort()
	return orphans


## Same shape as _compare_namespace_data: list what is at stake, then ask.
## Declining aborts the build so nothing is written.
static func _confirm_orphans(generated_files:Array, all_dirs:Array) -> bool:
	var orphans = _get_orphan_files(generated_files, all_dirs)
	if orphans.is_empty():
		return true

	print_rich("[color=fedd66]Generated files no longer claimed by any namespace config:[/color]")
	for path in orphans:
		print_rich("[color=fe786b]%s[/color]" % path)

	var message = \
"%s generated file(s) are no longer
claimed by any namespace config.
If you have moved their parent config,
or renamed their output path,
this is expected, otherwise confirm they are not valid

Delete them? This cannot be undone."
	var confirmed = await Dialog.confirm(message % orphans.size())
	if not confirmed:
		return false

	_delete_orphan_files(orphans)
	return true


static func _delete_orphan_files(orphans:Array):
	var parent_dirs = {}
	for path in orphans:
		DirAccess.remove_absolute(path)
		var uid_path = path + ".uid"
		if FileAccess.file_exists(uid_path):
			DirAccess.remove_absolute(uid_path)
		parent_dirs[path.get_base_dir()] = true

	# Deepest first, so a nested tree collapses in one pass. remove_absolute
	# fails harmlessly on a directory that still holds anything else.
	var dirs = parent_dirs.keys()
	dirs.sort_custom(func(a, b): return a.count("/") > b.count("/"))
	for dir in dirs:
		DirAccess.remove_absolute(dir)

	print("Removed %s orphaned generated file(s)." % orphans.size())


## Groups the roots found in the tags by the directory they build into.
static func _map_roots_to_dirs(claims:Dictionary, namespace_data:Dictionary, default_dir:String) -> Dictionary:
	var root_dirs = claims.get("root_dirs", {})
	var dir_to_roots = {}
	for root in namespace_data.keys():
		var dir = root_dirs.get(root, default_dir)
		if not dir_to_roots.has(dir):
			dir_to_roots[dir] = []
		dir_to_roots[dir].append(root)
	return dir_to_roots


## Every directory this build accounts for: the ones named by config (even if
## their claims lost a clash), the ones this build writes to, and the default.
## The default must be included even when nothing resolves to it, otherwise a
## root that just moved into a claimed directory leaves its old files behind.
## Anything generated outside this set is an orphan, handled by _confirm_orphans.
static func _get_dirs_to_clear(config:Dictionary, dir_to_roots:Dictionary, default_dir:String) -> Array:
	var clear_set = {default_dir: true}
	for dir in config.get("output_dirs", []):
		clear_set[dir] = true
	for dir in dir_to_roots.keys():
		clear_set[dir] = true
	var dirs = clear_set.keys()
	dirs.sort()
	return dirs


## Returns false when anything fatal was found, meaning a config could not be
## applied as written. Continuing past that would drop its claims to the default
## directory and let the orphan check offer to delete the output it left behind.
static func _report_config_errors(config:Dictionary) -> bool:
	var errors = config.get("errors", [])
	for error in errors:
		if error.get("type") == NamespaceConfig.ConfigError.FATAL:
			printerr("Namespace config - %s" % error.get("text"))
		else:
			print_rich("[color=fedd66]Namespace config - %s[/color]" % error.get("text"))

	return not NamespaceConfig.has_fatal(errors)


## Clashes and unused excludes both depend on the tag scan, so these are reported
## separately from the parse errors above.
static func _report_claims(config:Dictionary, claims:Dictionary, root_sources:Dictionary):
	for clash in claims.get("clashes", []):
		var message = "[color=fedd66]Namespace claim clash for '%s': using %s, ignoring %s[/color]"
		print_rich(message % [clash.get("root"), clash.get("winner"), clash.get("loser")])

	for unused in NamespaceConfig.get_unused_excludes(config.get("configs", []), root_sources):
		var message = "[color=fedd66]%s excludes '%s' but nothing under it declares that namespace.[/color]"
		print_rich(message % [unused.get("path"), unused.get("root")])


static func _get_used_namespace_references(output_dirs:Array=[]):
	if output_dirs.is_empty():
		output_dirs = get_all_output_dirs()
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
		if _path_in_dirs(file_path, output_dirs):
			continue
		var file_access = FileAccess.open(file_path, FileAccess.READ)
		var file_path_data = {}
		var count = 1
		while not file_access.eof_reached():
			var line = file_access.get_line()
			# Generated files outside the output dirs land here, and their own
			# "class_name X" line matches the reference pattern. Reporting that
			# would flag the files the orphan check is about to offer to delete.
			if count == 1 and line == GENERATED_HEADER:
				break
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
		
		var confirmed = await Dialog.confirm("Some references will be broken by\nnew namespace generated.\nProceed?")
		if not confirmed:
			return false
	
	return true

static func _check_script_for_member(script_path:String, scripts_dict:Dictionary, member_to_check:String):
	if member_to_check == "new":
		return true # this doesnt appear in members
	
	if not scripts_dict.has(script_path):
		var script = load(script_path)
		var script_data = {}
		var s_members = UClassDetail.script_get_all_members(script).keys()
		script_data["script"] = s_members
		var c_members = UClassDetail.class_get_all_members(script).keys()
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


## Removes only files carrying GENERATED_HEADER. Output directories may sit
## inside an addon alongside its own scripts, so anything else is left alone.
## .uid files are preserved here and reconciled in _clean_up_uids.
static func _clear_directory(directory: String):
	var dir_arrays = UFile.scan_for_dirs(directory, true)
	for array in dir_arrays:
		array.reverse()
		for dir in array:
			var dir_access = DirAccess.open(dir)
			if not dir_access:
				continue
			var files = dir_access.get_files()
			for f in files:
				var file_path = dir.path_join(f)
				if not _is_generated_file(file_path):
					continue
				DirAccess.remove_absolute(file_path)

	if not DirAccess.dir_exists_absolute(directory):
		return
	var dir_access = DirAccess.open(directory)
	if not dir_access:
		printerr("Could not open output directory: ", directory)
		return
	var files = dir_access.get_files()
	for file in files:
		var file_path = directory.path_join(file)
		if not _is_generated_file(file_path):
			continue
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
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	
	var dir_arrays = UFile.scan_for_dirs(directory, true)
	for array in dir_arrays:
		array.reverse()
		for dir in array:
			var dir_access = DirAccess.open(dir)
			if not dir_access:
				continue
			# Without this a directory holding only dotfiles reads as empty below.
			dir_access.include_hidden = true
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
	if not dir_access:
		printerr("Could not open output directory: ", directory)
		return
	dir_access.include_hidden = true
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


## generated_files_out collects every file carrying GENERATED_HEADER. Free to
## gather here: the first line this already reads looking for the tag is exactly
## the header check, and _confirm_orphans needs the full project-wide list.
## root_sources_out maps each top level namespace to the files that tagged it,
## which is what decides who claims it in NamespaceConfig.resolve_claims.
static func _scan_and_parse_namespaces(generated_files_out:Array=[], root_sources_out:Dictionary={}) -> Variant:
	var lines_to_check = 10
	var data = {}
	var all_files = UFile.scan_for_files(_RES, ["gd"])
	for file_path in all_files:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			printerr("Could not open file: ", file_path)
			continue
		
		for i in range(lines_to_check):
			var line = file.get_line()
			if i == 0 and line == GENERATED_HEADER:
				generated_files_out.append(file_path) # our own output, never tagged
				break
			if line.begins_with(NAMESPACE_TAG):
				var namespace_string = line.trim_prefix(NAMESPACE_TAG).strip_edges()
				if not namespace_string.is_empty():
					var success = _add_to_namespace_data(data, line, file_path)
					#var success = _add_to_namespace_data(data, namespace_string, file_path)
					if not success:
						return false
					var parts = get_namespace_string_parts(line)
					if not parts.is_empty():
						var root = parts[0]
						if not root_sources_out.has(root):
							root_sources_out[root] = []
						root_sources_out[root].append(file_path)
				break
		
		file.close()
	
	return data


#region MULTI FILE NAMESPACE

# Main entry point. Generates the given roots into one directory.
# Roots are passed explicitly because a build may split them across directories;
# an empty array means "every root in data".
static func _generate_namespace_file_with_dir(data: Dictionary, generated_dir: String, roots:Array=[]):
	DirAccess.make_dir_recursive_absolute(generated_dir)
	if roots.is_empty():
		roots = data.keys()
		roots.sort()
	for top_level_class_name in roots:
		var sub_data = data[top_level_class_name]
		_generate_class_and_subclasses(top_level_class_name, sub_data, generated_dir, generated_dir, true)


static func _generate_class_and_subclasses(_class_name: String, data: Dictionary, parent_dir_path: String, generated_dir, is_root:=false):
	var file_name = _class_name.to_snake_case() + ".gd"
	var file_path = parent_dir_path.path_join(file_name)

	var child_dir_path = parent_dir_path.path_join(_class_name.to_snake_case())

	var file_content = GENERATED_HEADER + "\n\n"
	# Explicit flag rather than comparing paths: output dirs now come from user
	# authored config and pass through simplify_path/path_join on the way here.
	if is_root:
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
		var file_content = GENERATED_HEADER + "\n\n"
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


## Prefers the plugin's cache. Falls back to reading from disk so this still
## works with the plugin disabled.
static func get_namespace_classes() -> Dictionary:
	var plugin = Plugin.get_instance()
	if plugin:
		return plugin.namespace_classes
	return build_namespace_classes(get_all_output_dirs())


## Top level of every output directory. Reads class_name straight out of the
## files rather than filtering ProjectSettings.get_global_class_list(), because
## the rescan after a build is asynchronous and would not yet list a root that
## was just generated. These are files we wrote, so their header and class_name
## are authoritative the moment generation finishes.
static func build_namespace_classes(output_dirs:Array) -> Dictionary:
	var namespace_classes = {}
	for namespace_dir in output_dirs:
		if not DirAccess.dir_exists_absolute(namespace_dir):
			continue
		for f in DirAccess.get_files_at(namespace_dir):
			var path = namespace_dir.path_join(f)
			if not _is_generated_file(path):
				continue
			var _class_name = _read_generated_class_name(path)
			if not _class_name.is_empty():
				namespace_classes[_class_name] = path

	return namespace_classes


## Sub namespace files are plain scripts, so a missing class_name just means this
## is not a root and the file is skipped.
static func _read_generated_class_name(path:String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var found = ""
	# The declaration sits right after the header, but a few lines of slack keeps
	# this from breaking if the generated preamble ever grows.
	for i in range(5):
		if file.eof_reached():
			break
		var line = file.get_line().strip_edges()
		if line.begins_with("class_name "):
			found = line.trim_prefix("class_name ").strip_edges()
			break
	file.close()
	return found

static func get_namespace_class_maps():
	var namespace_classes = get_namespace_classes()
	var map = {}
	for name in namespace_classes.keys():
		var path = namespace_classes.get(name)
		var script = load(path)
		var preloads = UClassDetail.script_get_preloads(script, true)
		if not preloads.is_empty():
			var paths = []
			map[path] = preloads
			for p in preloads.keys():
				var p_script = preloads[p]
				var p_path = p_script.resource_path
				map[p_path] = path
	
	return map


static func class_name_in_script(word, script):
	var const_map = script.get_script_constant_map()
	if const_map.has(word):
		return const_map.get(word)
