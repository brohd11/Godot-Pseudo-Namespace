@tool
extends EditorScript

func _run() -> void:
	NamespaceBuilder.build_files()

const NamespaceBuilder = preload("res://addons/namespace/src/namespace_builder.gd")
