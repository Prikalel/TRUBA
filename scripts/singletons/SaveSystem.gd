# Persisted-level save manager.
#
# Stores only the resource path (res://...) of the level the player is currently
# in, so the title screen's "Начать" button can resume the game there after the
# browser tab is closed and reopened.
#
# Storage strategy (HTML5 export target):
#   * Primary — browser localStorage (survives tab close/reopen).
#   * Fallback — user://truba_save.json for desktop/editor runs.
#
# The JavaScript engine singleton only exists in HTML5 builds, so it is looked
# up through Engine (has_singleton/get_singleton) — never via the bare
# `JavaScript` global class — so this script parses fine in the desktop editor.
# localStorage access requires use_global_context = true (the 2nd eval arg).

extends Node

# localStorage key / fallback file name version. Bump if the save format changes.
const KEY := "truba_save_v1"
# Desktop-only fallback file. Unused on the web (localStorage is used instead).
const DESKTOP_FILE := "user://truba_save.json"


# --- Public API ---------------------------------------------------------------

# Store the given level's resource path as the current save point.
func save_level(scene_resource_path: String) -> void:
	var data := {"level": scene_resource_path}
	var text := to_json(data)
	if _is_web() and Engine.has_singleton("JavaScript"):
		var js := Engine.get_singleton("JavaScript")
		js.eval("localStorage.setItem('%s', '%s')" % [KEY, _js_escape(text)], true)
	else:
		var f := File.new()
		if f.open(DESKTOP_FILE, File.WRITE) == OK:
			f.store_string(text)
			f.close()


# Return the saved level's res:// path, or "" if there is none / it is invalid.
func get_saved_level() -> String:
	var text := ""
	if _is_web() and Engine.has_singleton("JavaScript"):
		var js := Engine.get_singleton("JavaScript")
		var raw = js.eval("localStorage.getItem('%s')" % KEY, true)
		# localStorage.getItem returns the stored string or JS null.
		if typeof(raw) == TYPE_STRING:
			text = raw
	else:
		var f := File.new()
		if f.open(DESKTOP_FILE, File.READ) == OK:
			text = f.get_as_text()
			f.close()
	if text == "":
		return ""
	var parsed = JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return ""
	return String(parsed.result.get("level", ""))


# True if a non-empty saved level exists.
func has_save() -> bool:
	return get_saved_level() != ""


# Wipe the save. Intended for debugging / explicit "new game" flows only — the
# normal return-to-menu path deliberately leaves the save intact.
func clear_save() -> void:
	if _is_web() and Engine.has_singleton("JavaScript"):
		var js := Engine.get_singleton("JavaScript")
		js.eval("localStorage.removeItem('%s')" % KEY, true)
	else:
		var f := File.new()
		if f.open(DESKTOP_FILE, File.WRITE) == OK:
			f.store_string("")
			f.close()


# --- Internals ----------------------------------------------------------------

func _is_web() -> bool:
	return OS.has_feature("HTML5")


# Make `s` safe to embed inside a single-quoted JS string literal. Order matters:
# backslashes first (so we don't double-escape the ones we add), then single
# quotes, then control chars — to_json emits literal \n / \t which would
# otherwise terminate/break the JS string literal.
func _js_escape(s: String) -> String:
	return s \
		.replace("\\", "\\\\") \
		.replace("'", "\\'") \
		.replace("\r", "\\r") \
		.replace("\n", "\\n") \
		.replace("\t", "\\t")
