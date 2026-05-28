@tool
extends EditorPlugin

## Editor-side glue for the Journey Engine Core addon. Its only job is to register
## (and de-register) the `JourneyRuntime` autoload so consumers don't have to add
## it by hand — enabling the plugin in Project Settings > Plugins is the whole
## install step.
##
## The runtime itself (journey_runtime.gd and the rest of this folder) is plain
## GDScript with NO editor dependency; this plugin is purely a convenience and is
## never loaded at game runtime.

const AUTOLOAD_NAME := "JourneyRuntime"
const AUTOLOAD_PATH := "res://addons/journey_engine_core/journey_runtime.gd"

## Tracks whether THIS plugin session registered the autoload, so _exit_tree only
## removes what it added. Without this, disabling the plugin would strip a
## pre-existing autoload the plugin never created — e.g. the entry this repo
## commits in project.godot so the sample game runs even with the plugin off.
var _added_autoload := false

func _enter_tree() -> void:
	# Only register if the project doesn't already declare the autoload (a user
	# added it by hand, or it's committed in project.godot). add_autoload_singleton
	# would otherwise push a "duplicate" error. Remember if we added it so the
	# remove on _exit_tree stays symmetric.
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
		_added_autoload = true

func _exit_tree() -> void:
	# Remove ONLY if this session added it — never delete a manually-declared
	# autoload the plugin doesn't own.
	if _added_autoload:
		remove_autoload_singleton(AUTOLOAD_NAME)
		_added_autoload = false
