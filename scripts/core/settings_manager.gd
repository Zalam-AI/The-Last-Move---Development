extends Node
## SettingsManager (autoload: Settings)
## Single source of truth for user options: display, graphics, audio, controls,
## accessibility. Persists to user://settings.cfg and re-applies on boot.

signal changed

const CFG_PATH := "user://settings.cfg"
const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E],
	"throw": [KEY_G],
	"rotate_left": [KEY_Q],
	"rotate_right": [KEY_R],
	"flashlight": [KEY_F],
	"scoreboard": [KEY_TAB],
	"push_to_talk": [KEY_V],
	"pause": [KEY_ESCAPE],
	"emote": [KEY_X],
}

var data := {
	# video
	"fullscreen": false,
	"vsync": true,
	"fps_limit": 0,
	"render_scale": 1.0,
	"shadows": 2,
	"aa": 1,
	# audio
	"vol_master": 0.9,
	"vol_music": 0.55,
	"vol_sfx": 0.9,
	"vol_ambience": 0.7,
	"vol_voice": 1.0,
	# voice
	"voice_enabled": true,
	"voice_push_to_talk": true,
	"mic_device": "",
	"mic_gain": 1.0,
	# controls
	"sensitivity": 1.0,
	"fov": 85.0,
	"invert_y": false,
	# accessibility / comfort
	"head_bob": 1.0,
	"camera_shake": 1.0,
	"motion_blur": false,
	"subtitles": true,
	"subtitle_background": true,
	"text_scale": 1.0,
	"reduce_flashing": false,
	"view_sway": 1.0,
	"language": "en",
	"player_name": "",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_input_map()
	load_settings()
	if data["player_name"] == "":
		data["player_name"] = "Mover %d" % (randi() % 900 + 100)


func ensure_input_map() -> void:
	for action in ACTIONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			var exists := false
			for old in InputMap.action_get_events(action):
				if old is InputEventKey and old.physical_keycode == key:
					exists = true
			if not exists:
				InputMap.action_add_event(action, ev)
	# mouse buttons
	if not _action_has_mouse("interact", MOUSE_BUTTON_LEFT):
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("interact", mb)
	if not _action_has_mouse("throw", MOUSE_BUTTON_RIGHT):
		var mb2 := InputEventMouseButton.new()
		mb2.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("throw", mb2)


func _action_has_mouse(action: String, button: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and e.button_index == button:
			return true
	return false


func get_value(key: String, default_value: Variant = null) -> Variant:
	return data.get(key, default_value)


func set_value(key: String, value: Variant) -> void:
	if data.get(key) == value:
		return
	data[key] = value
	apply_one(key)
	save_settings()
	changed.emit()


func apply_all() -> void:
	for key in data.keys():
		apply_one(key)
	changed.emit()


func apply_one(key: String) -> void:
	match key:
		"fullscreen":
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if data["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)
		"fps_limit":
			Engine.max_fps = int(data["fps_limit"])
		"render_scale":
			get_viewport().scaling_3d_scale = clampf(float(data["render_scale"]), 0.5, 1.0) if is_inside_tree() else 1.0
		"shadows":
			if is_inside_tree():
				var q := int(data["shadows"])  # 0 off, 1 low, 2 high
				get_viewport().positional_shadow_atlas_size = 0 if q == 0 else (2048 if q == 1 else 4096)
				get_viewport().positional_shadow_atlas_16_bits = q < 2
		"aa":
			if is_inside_tree():
				get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(int(data["aa"]), 0, 2)]
		"vol_master":
			_set_bus("Master", data["vol_master"])
		"vol_music":
			_set_bus("Music", data["vol_music"])
		"vol_sfx":
			_set_bus("SFX", data["vol_sfx"])
		"vol_ambience":
			_set_bus("Ambience", data["vol_ambience"])
		"vol_voice":
			_set_bus("Voice", data["vol_voice"])


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, float(linear))))
	AudioServer.set_bus_mute(idx, float(linear) <= 0.001)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("settings", key, data[key])
	var err := cfg.save(CFG_PATH)
	if err != OK:
		push_warning("Settings save failed: %s" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for key in data.keys():
		if cfg.has_section_key("settings", key):
			var v = cfg.get_value("settings", key)
			if typeof(v) == typeof(data[key]) or (data[key] is float and v is int):
				data[key] = v
