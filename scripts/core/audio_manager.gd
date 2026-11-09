extends Node
## AudioManager (autoload: Audio)
## Owns the audio buses, a pool of 3D one-shots, pooled UI players, music crossfading
## and ambience layers. All clips are loaded from res://assets/audio (generated offline
## by tools/generate_audio.py). Missing clips are reported once and degrade silently so
## content work never breaks a build.

signal voice_line(text: String, seconds: float)

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMB_DIR := "res://assets/audio/ambience/"
const VOICE_DIR := "res://assets/audio/voice/"

const POOL_3D := 28
const POOL_2D := 8
const VARIATION_PITCH := 0.09

var streams: Dictionary = {}          # base_name -> Array[AudioStream]
var music_streams: Dictionary = {}
var amb_streams: Dictionary = {}
var voice_streams: Dictionary = {}    # base_name -> Array[AudioStream] (or text keyed TTS)
var missing: Dictionary = {}

var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _next3d := 0
var _next2d := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active_is_a := true
var _music_tween: Tween
var _amb_players: Array[AudioStreamPlayer] = []
var _current_music := ""
var _current_amb := ""


func _ready() -> void:
	_setup_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 45.0
		p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_db = 3.0
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var q := AudioStreamPlayer.new()
		q.bus = "SFX"
		add_child(q)
		_pool2d.append(q)
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = "Music"
	_music_a.volume_db = -80.0
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = "Music"
	_music_b.volume_db = -80.0
	add_child(_music_b)
	for i in 3:
		var amb := AudioStreamPlayer.new()
		amb.bus = "Ambience"
		amb.volume_db = -80.0
		add_child(amb)
		_amb_players.append(amb)
	_scan_all()


func _setup_buses() -> void:
	var wanted := [
		{"name": "Music", "parent": "Master"},
		{"name": "SFX", "parent": "Master"},
		{"name": "Ambience", "parent": "Master"},
		{"name": "Voice", "parent": "Master"},
	]
	for w in wanted:
		if AudioServer.get_bus_index(w["name"]) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, w["name"])
			AudioServer.set_bus_send(idx, w["parent"])
	# Voice bus gets a gentle compressor so shouting does not clip teammates' ears.
	var vi := AudioServer.get_bus_index("Voice")
	if vi >= 0 and AudioServer.get_bus_effect_count(vi) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -12.0
		comp.ratio = 3.0
		AudioServer.add_bus_effect(vi, comp)


const MANIFEST_PATH := "res://assets/audio/manifest.json"


func _scan_all() -> void:
	# The manifest is authoritative: in an exported .pck the imported file names differ
	# from the source names, so directory scanning alone silently drops clips.
	if _load_manifest():
		_report_banks()
		return
	_scan_dir(SFX_DIR, streams, true)
	_scan_dir(MUSIC_DIR, music_streams, false)
	_scan_dir(AMB_DIR, amb_streams, false)
	_scan_dir(VOICE_DIR, voice_streams, false)
	_report_banks()


func _report_banks() -> void:
	var total := 0
	for k in streams.keys():
		total += streams[k].size()
	print("[Audio] %d sfx clips, %d music, %d ambience, %d voice" % [total, music_streams.size(), amb_streams.size(), voice_streams.size()])


func _load_manifest() -> bool:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false
	var raw := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var banks := {
		"sfx": streams,
		"music": music_streams,
		"ambience": amb_streams,
		"voice": voice_streams,
	}
	var loaded := 0
	for bank_name in banks.keys():
		var entries: Variant = parsed.get(bank_name, {})
		if typeof(entries) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = banks[bank_name]
		for key in entries.keys():
			var paths: Variant = entries[key]
			if typeof(paths) != TYPE_ARRAY:
				continue
			var list: Array = []
			for path in paths:
				var stream := load(str(path))
				if stream is AudioStream:
					list.append(stream)
			if not list.is_empty():
				target[str(key)] = list
				loaded += list.size()
	return loaded > 0


func _scan_dir(path: String, target: Dictionary, strip_variants: bool) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname
			if clean.ends_with(".import"):
				clean = clean.trim_suffix(".import")
			if clean.get_extension() in ["wav", "ogg", "mp3"]:
				var stem := clean.get_basename()
				var base := _base_name(stem) if strip_variants else stem
				var stream := load(path + clean)
				if stream is AudioStream:
					if not target.has(base):
						target[base] = []
					target[base].append(stream)
		fname = dir.get_next()
	dir.list_dir_end()


## "wood_scrape_03" -> "wood_scrape"; "door_open" -> "door_open"
func _base_name(stem: String) -> String:
	var parts := stem.rsplit("_", false, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return parts[0]
	return stem


func has_sfx(base: String) -> bool:
	return streams.has(base)


# ------------------------------------------------------------------- sfx ----

func play_sfx(base: String, position = null, volume_db := 0.0, pitch := 1.0, bus := "SFX") -> void:
	var arr: Array = streams.get(base, [])
	if arr.is_empty():
		_report_missing(base)
		return
	var stream: AudioStream = arr[randi() % arr.size()]
	if position == null or not (position is Vector3):
		_play_2d(stream, volume_db, pitch * (1.0 + randf_range(-VARIATION_PITCH, VARIATION_PITCH)), bus)
	else:
		_play_3d(stream, position, volume_db, pitch * (1.0 + randf_range(-VARIATION_PITCH, VARIATION_PITCH)), bus)


func play_impact(material: String, intensity: float, position: Vector3) -> void:
	var v := clampf(intensity, 0.0, 1.0)
	var set_name: String = "imp_%s" % material
	if not streams.has(set_name):
		set_name = "imp_default"
	var vol := lerpf(-16.0, 4.0, v)
	play_sfx(set_name, position, vol, lerpf(1.15, 0.85, v))
	if v > 0.6 and streams.has("break_%s" % material):
		play_sfx("break_%s" % material, position, lerpf(-10.0, 0.0, v))


func play_scrape(material: String, position: Vector3, intensity: float) -> void:
	var n := "scrape_%s" % material
	if not streams.has(n):
		n = "scrape_default"
	play_sfx(n, position, lerpf(-22.0, -6.0, clampf(intensity, 0.0, 1.0)), randf_range(0.92, 1.08))


func _play_3d(stream: AudioStream, pos: Vector3, volume_db: float, pitch: float, bus: String) -> void:
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.stream = stream
	p.bus = bus
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()


func _play_2d(stream: AudioStream, volume_db: float, pitch: float, bus: String) -> void:
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = stream
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()


func _report_missing(base: String) -> void:
	if not missing.has(base):
		missing[base] = true
		push_warning("[Audio] missing clip: %s" % base)


# ---------------------------------------------------------------- music -----

func play_music(name: String, fade := 1.6) -> void:
	if name == _current_music:
		return
	var arr: Array = music_streams.get(name, [])
	if arr.is_empty():
		if name != "":
			_report_missing("music:" + name)
		return
	_current_music = name
	var incoming := _music_b if _music_active_is_a else _music_a
	var outgoing := _music_a if _music_active_is_a else _music_b
	_music_active_is_a = not _music_active_is_a
	var stream: AudioStream = arr[0]
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", -8.0, fade)
	_music_tween.tween_property(outgoing, "volume_db", -60.0, fade)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade := 1.5) -> void:
	_current_music = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, fade)
			t.tween_callback(p.stop)


func current_music() -> String:
	return _current_music


# ------------------------------------------------------------ ambience -----

func play_ambience(name: String, fade := 2.0, volume_db := -10.0) -> void:
	if name == _current_amb:
		return
	_current_amb = name
	var arr: Array = amb_streams.get(name, [])
	if arr.is_empty():
		if name != "":
			_report_missing("amb:" + name)
		return
	for p in _amb_players:
		if p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, fade)
			t.tween_callback(p.stop)
	var stream: AudioStream = arr[0]
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var p2 := _amb_players[0]
	p2.stream = stream
	p2.volume_db = -60.0
	p2.play()
	var tw := create_tween()
	tw.tween_property(p2, "volume_db", volume_db, fade)


func stop_ambience(fade := 1.5) -> void:
	_current_amb = ""
	for p in _amb_players:
		if p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -60.0, fade)
			t.tween_callback(p.stop)


func ambience_name() -> String:
	return _current_amb


# --------------------------------------------------------------- voice -----

## Plays a pre-generated announcement/voice clip and emits subtitles for it.
func play_voice(base: String, subtitle_text := "", volume_db := 0.0) -> void:
	var arr: Array = voice_streams.get(base, [])
	if arr.is_empty():
		_report_missing("voice:" + base)
		return
	var stream: AudioStream = arr[0]
	var dur := stream.get_length() if stream != null else 3.0
	var p: AudioStreamPlayer = _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	p.stream = stream
	p.bus = "Voice"
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()
	if subtitle_text != "":
		voice_line.emit(subtitle_text, maxf(1.0, dur))


func voice_clip_count() -> int:
	return voice_streams.size()
