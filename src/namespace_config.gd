@tool
extends RefCounted
#! remote
const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/u_file.gd")

@warning_ignore_start("static_called_on_instance")

enum ConfigError {
	WARNING,
	FATAL
}

const _RES = "res://"

## Files that may carry a [namespace] section. All are treated identically.
const CONFIG_NAMES = ["plugin.cfg", "version.cfg", "namespace.cfg"]
const SECTION = "namespace"
const PATH_KEY = "path"
const EXCLUDE_KEY = "exclude"
## No longer read. Kept so a stale config can be reported instead of silently
## doing nothing.
const LEGACY_CLASSES_KEY = "classes"

## Output dir used when a section declares no path.
const DEFAULT_PATH = "namespace"


static func normalize_dir(path:String) -> String:
	var normalized = path.simplify_path()
	if not normalized.ends_with("/"):
		normalized += "/"
	return normalized


## Godot's filesystem scanner skips any directory beginning with ".", so nothing
## generated inside one is ever indexed: the global class_name is never
## registered and preloads by uid never resolve. Every segment is tested, not
## just the last, so a hidden component anywhere in the path is caught, including
## the case of a config file that itself lives under a hidden directory.
static func is_hidden_path(path:String) -> bool:
	for part in path.trim_prefix(_RES).split("/", false):
		if part.begins_with("."):
			return true
	return false


static func has_fatal(errors:Array) -> bool:
	for error in errors:
		if error.get("type") == ConfigError.FATAL:
			return true
	return false


## Every .cfg in the project whose name is in CONFIG_NAMES, sorted by full path.
## Sorting makes the "first claim wins" rule a total order that is obvious from
## the config paths alone.
static func find_config_files(root:=_RES) -> Array:
	var config_files = []
	var search = UFile.GetFiles.open(root)
	search.file_extensions = ["cfg"]
	search.ignore_dir_names = ".git"
	var files = search.get_files()
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
		errors.append(get_error("%s: path '%s' resolves outside res://" % [config_path, output], ConfigError.FATAL))
		return ""
	if resolved == _RES:
		errors.append(get_error("%s: path '%s' resolves to the project root" % [config_path, output], ConfigError.FATAL))
		return ""

	# After resolution, so a config that itself sits under a hidden directory is
	# caught even when the path it declares looks innocent. Ordered last so an
	# escaping path reports the more specific problem.
	if is_hidden_path(resolved):
		var message = "%s: path '%s' resolves into a hidden directory (%s). Godot does not index those, so nothing generated there would load."
		errors.append(get_error(message % [config_path, output, resolved], ConfigError.FATAL))
		return ""

	return resolved


## Reads the [namespace] section of one config file.
## Returns {} when the file has no such section, so plain plugin.cfg files are
## skipped silently.
static func _parse_config_file(config_path:String, errors:Array) -> Dictionary:
	var config = ConfigFile.new()
	var err = config.load(config_path)
	if err != OK:
		errors.append(get_error("%s: could not read config (error %s)" % [config_path, err], ConfigError.FATAL))
		return {}

	if not config.has_section(SECTION):
		return {}

	var output = _resolve_output(str(config.get_value(SECTION, PATH_KEY, "")), config_path, errors)
	if output.is_empty():
		return {}
	
	
	var raw_exclude = config.get_value(SECTION, EXCLUDE_KEY, [])
	if raw_exclude == null:
		raw_exclude = []
	if not raw_exclude is Array and not raw_exclude is PackedStringArray:
		# Fatal: every exclusion is dropped, so this config would claim namespaces
		# it was told to leave alone.
		errors.append(get_error("%s: '%s' must be an array." % [config_path, EXCLUDE_KEY], ConfigError.FATAL))
		raw_exclude = []

	var exclude = []
	for entry in raw_exclude:
		var _class_name = str(entry).strip_edges()
		if _class_name.is_empty():
			continue
		if _class_name.contains("."):
			var message = "%s: '%s' is not valid, only top level namespace names may be excluded."
			errors.append(get_error(message % [config_path, _class_name], ConfigError.FATAL))
			continue
		if not _class_name.is_valid_ascii_identifier():
			errors.append(get_error("%s: '%s' is not a valid class name." % [config_path, _class_name], ConfigError.FATAL))
			continue
		exclude.append(_class_name)

	return {
		"path": config_path,
		# Trailing slash, so a prefix test cannot match a sibling like ns_old/.
		"dir": normalize_dir(config_path.get_base_dir()),
		"output": output,
		"exclude": exclude,
	}

static func get_error(text:String, type:ConfigError):
	return {"text": text, "type": type}

## Config discovery only. Deliberately does not scan .gd files: which roots a
## config claims depends on the namespace tags, but where output goes does not,
## and the editor cache only ever needs the latter.
static func load_all(default_dir:String) -> Dictionary:
	default_dir = normalize_dir(default_dir)

	var configs = []
	var output_dirs = {default_dir: true}
	var errors = []

	# Not a config file, but it fails the same way and everything unclaimed builds
	# there, so it goes through the same errors array and the same abort gate.
	if is_hidden_path(default_dir):
		var message = "Default output directory '%s' is a hidden directory. Godot does not index those, so nothing generated there would load."
		errors.append(get_error(message % default_dir, ConfigError.FATAL))

	for config_path in find_config_files():
		var parsed = _parse_config_file(config_path, errors)
		if parsed.is_empty():
			continue
		configs.append(parsed)
		# Recorded even when this config ends up claiming nothing, so output left
		# from a claim that has since moved away still gets cleared.
		output_dirs[parsed.output] = true

	var sorted_dirs = output_dirs.keys()
	sorted_dirs.sort()

	return {
		"configs": configs, # already in config path order, find_config_files sorts
		"output_dirs": sorted_dirs,
		"errors": errors,
	}


## The config that owns a file: the one whose directory is the longest prefix of
## it. Configs excluding this root are skipped, so a claim falls through to the
## next nearest ancestor rather than straight to the default.
static func _owning_config(file_path:String, root:String, configs:Array):
	var owner = null
	for config in configs:
		if not file_path.begins_with(config.dir):
			continue
		if root in config.exclude:
			continue
		if owner == null or config.dir.length() > owner.dir.length():
			owner = config
	return owner


## Which directory each root builds into. A root is claimed by the config owning
## its tagged files; files resolving to more than one config is a real ambiguity,
## so the first by config path wins and the rest are reported.
static func resolve_claims(configs:Array, root_sources:Dictionary) -> Dictionary:
	var root_dirs = {}
	var sources = {}
	var clashes = []

	var roots = root_sources.keys()
	roots.sort()

	for root in roots:
		var owners = []
		for file_path in root_sources[root]:
			var owner = _owning_config(file_path, root, configs)
			if owner == null:
				continue # unclaimed, this file falls to the default directory
			if not owners.has(owner):
				owners.append(owner)

		if owners.is_empty():
			continue

		# configs arrive in path order, so the first owner found is the winner
		var winner = owners[0]
		for other in owners:
			if other.path < winner.path:
				winner = other

		root_dirs[root] = winner.output
		sources[root] = winner.path

		for other in owners:
			if other == winner:
				continue
			clashes.append({"root": root, "winner": winner.path, "loser": other.path})

	return {
		"root_dirs": root_dirs,
		"sources": sources,
		"clashes": clashes,
	}


## Excluded names that no tag under that config actually produces, which almost
## always means a typo.
static func get_unused_excludes(configs:Array, root_sources:Dictionary) -> Array:
	var unused = []
	for config in configs:
		for root in config.exclude:
			if not root_sources.has(root):
				unused.append({"root": root, "path": config.path})
				continue
			var found = false
			for file_path in root_sources[root]:
				if file_path.begins_with(config.dir):
					found = true
					break
			if not found:
				unused.append({"root": root, "path": config.path})
	return unused


## This module holds no state. The editor side caches what it needs on the plugin
## instance, and a build always loads fresh.
