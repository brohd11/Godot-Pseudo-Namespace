## Namespace Generator

This plugin will generate files for you based on how you tag your files.

The files generated use UIDs to preload the class, so they are resilient to moving around files.

### How to Use

First off, be sure to save all files before running the build.

You can create a namespace by writing a tag near the top of your script (within the top 10 lines).

```
extends SomeClass
#! namespace MyNameSpace.ThisClass
```

This will generate the file `my_name_space.gd` as global class `MyNameSpace`.

Inside, it will have the script preloaded to provide access to the class:

`const ThisClass = preload("path/to/this/class.gd")` 

You can do as many sub classes as you want:

```
#! namespace MyNameSpace.SubSpace.Sub.Sub.Sub.ThisClass
```

Each sub class will be another file created in the namespace directory.
The last identifier will always be the current scripts identifier.

If you have the syntax highlighter active, there will be a few (configurable) colors that appear. they can be adjusted in Editor Settings.

These will always apply:
 - Green - A new namespace or class declaration
 - Red - Name clash with global script or built-in type

These will appear once files are generated:
 - Dark Blue - Existing namespace or class
 - Light Blue - The current script's namespace location
 - Dark Red - Name clash with another script in the namespace


Once you have your initial scripts setup, you should then set the location for your generated classes. You can do this in the project settings, or from the EditorConsole plugin:

`namespace set-dir -- my/dir`

"res://" will be added to the front if you use a relative path. This directory will be completely erased everytime you run the build, so don't place anything inside, or make changes you need preserved.

Now you can run the build process by either running the EditorScript "namespace_builder.gd",
or from the console:

`namespace build`

If there are existing namespace files, before deleting anything, it will parse the existing files, and all scripts in your projects to check if your new configuration will break any references. It will list them if so and you can decide whether to proceed or not.

When accessing the namespace class, there is a code completion plugin that will activate. It will give better results than the standard autocomplete when extending and assigning variables. If you have existing namespace files, it will also display members when declaring a namespace.

Because you access this as a global class, you could move these files wherever needed without issues. For example into a plugin for a release package. Alternatively, you can use my [Plugin Exporter](https://github.com/brohd11/Godot-Plugin-Exporter) to keep them in a central spot and package them in with your plugin on export. This is good for utilities or modules you use in multiple projects.

### Sub Plugins

The plugin includes 2 sub plugins, EditorConsole and SyntaxPlus.

The console provides a quick way to build and set the directory without having to run the script as EditorScript or going into ProjectSettings.

SyntaxPlus will provide highlighting for the namespace declaration, telling you if a new space is being created, there is a conflict or shadowing a global class.

Both are optional, and could be disabled if desired.