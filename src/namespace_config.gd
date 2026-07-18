@tool
extends RefCounted
#! remote
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")

@warning_ignore_start("static_called_on_instance")

const _RES = "res://"

## Files that may carry a [namespace] section. All are treated identically.
const CONFIG_NAMES = ["plugin.cfg", "version.cfg", "namespace.cfg"]
const SECTION = "namespace"
const PATH_KEY = "path"
const CLASSES_KEY = "classes"

## Output dir used when a config declares classes but no path.
const DEFAULT_PATH = "namespace"

## Full paths, not basenames: _scan_for_files compares against dir.path_join(d).
## Required, not an optimization, since the scan runs with include_hidden.
const SKIP_DIRS = ["res://.godot", "res://.git"]


static func normalize_dir(path:String) -> String:
	var normalized = path.simplify_path()
	if not normalized.ends_with("/"):
		normalized += "/"
	return normalized


## Every .cfg in the project whose name is in CONFIG_NAMES, sorted by full path.
## Sorting makes the "first claim wins" rule a total order that is obvious from
## the config paths alone.
static func find_config_files(root:=_RES) -> Array:
	var config_files = []
	var files = UFile.scan_for_files_no_fs(root, ["cfg"], false, SKIP_DIRS)
	for path in files:
		if path.get_file() in CONFIG_NAMES:
			config_files.append(path)
	config_files.sort()
	return config_files


## Resolves a [namespace] path value against the config file that declared it.
## Returns "" if the result escapes res:// or resolves to the project root.
static func _resolve_output(output:String, config_path:String, errors:Array) -> String:
	if output.is_empty():
		output = DEFAULT_PATH

	var resolved = output
	if not resolved.begins_with(_RES):
		resolved = config_path.get_base_dir().path_join(output)
	resolved = normalize_dir(resolved)

	# simplify_path() does not clamp at the resource root, it leaves the leading
	# ".." in place, so "res://../outside" still passes a begins_with check.
	if not resolved.begins_with(_RES) or resolved.trim_prefix(_RES).begins_with(".."):
		errors.append("%s: path '%s' resolves outside res://" % [config_path, output])
		return ""
	if resolved == _RES:
		errors.append("%s: path '%s' resolves to the project root" % [config_path, output])
		return ""

	return resolved


## Reads the [namespace] section of one config file.
## Returns {} when the file has no such section, so plain plugin.cfg files are
## skipped silently.
static func _parse_config_file(config_path:String, errors:Array) -> Dictionary:
	var config = ConfigFile.new()
	var err = config.load(config_path)
	if err != OK:
		errors.append("%s: could not read config (error %s)" % [config_path, err])
		return {}

	if not config.has_section(SECTION):
		return {}

	var output = _resolve_output(str(config.get_value(SECTION, PATH_KEY, "")), config_path, errors)
	if output.is_empty():
		return {}

	var raw_classes = config.get_value(SECTION, CLASSES_KEY, [])
	if raw_classes == null:
		raw_classes = []
	if not raw_classes is Array and not raw_classes is PackedStringArray:
		errors.append("%s: '%s' must be an array." % [config_path, CLASSES_KEY])
		return {"output": output, "classes": []}

	var classes = []
	for entry in raw_classes:
		var _class_name = str(entry).strip_edges()
		if _class_name.is_empty():
			continue
		if _class_name.contains("."):
			var message = "%s: '%s' is not valid, only top level namespace names may be declared."
			errors.append(message % [config_path, _class_name])
			continue
		if not _class_name.is_valid_ascii_identifier():
			errors.append("%s: '%s' is not a valid class name." % [config_path, _class_name])
			continue
		classes.append(_class_name)

	if classes.is_empty():
		errors.append("%s: [%s] section declares no classes." % [config_path, SECTION])

	return {"output": output, "classes": classes}


## Full project scan. Claims are global: a config's location decides only where
## output goes, never which source files it applies to.
static func load_all(default_dir:String) -> Dictionary:
	default_dir = normalize_dir(default_dir)

	var root_dirs = {}
	var sources = {}
	var output_dirs = {default_dir: true}
	var clashes = []
	var errors = []

	for config_path in find_config_files():
		var parsed = _parse_config_file(config_path, errors)
		if parsed.is_empty():
			continue

		# Recorded even when every claim below loses a clash, so output from a
		# since-removed claim still gets cleared.
		output_dirs[parsed.output] = true

		for _class_name in parsed.classes:
			if root_dirs.has(_class_name):
				clashes.append({
					"root": _class_name,
					"winner": sources.get(_class_name),
					"loser": config_path,
				})
				continue
			root_dirs[_class_name] = parsed.output
			sources[_class_name] = config_path

	var sorted_dirs = output_dirs.keys()
	sorted_dirs.sort()

	return {
		"root_dirs": root_dirs,
		"sources": sources,
		"output_dirs": sorted_dirs,
		"clashes": clashes,
		"errors": errors,
	}


## This module holds no state. The editor side caches what it needs on the plugin
## instance, and a build always loads fresh.
