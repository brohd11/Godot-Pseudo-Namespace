#class_name NamespaceUtil

const UFile = preload("res://addons/addon_lib/brohd/alib_runtime/utils/src/u_file.gd")


static func check_gits():
	for folder in DirAccess.get_directories_at("res://addons"):
		var path = "res://addons".path_join(folder)
		
		var dirty = _get_git_status(path)
		if dirty:
			print("Uncommmited changes in: %s" % path)

static func _get_git_status(dir):
	var args = [
		"-C",
		dir.replace("res://", ""),
		"diff",
		"--quiet",
		"--exit-code"
	]
	var output = []
	var exit_code = OS.execute("git", args, output)
	if exit_code == -1:
		printerr("Error getting git status: %s" % dir)
		return
	
	if exit_code == 0:
		return false
	elif exit_code == 1: #dirty
		return true
