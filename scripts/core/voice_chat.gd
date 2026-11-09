extends Node
## Proximity voice chat (real implementation).
##
## Capture: the microphone is played into a dedicated "VoiceCapture" bus that carries an
## AudioEffectCapture. We pull the ring buffer every frame, downsample to 16 kHz mono,
## quantise to 16-bit PCM and ship it as unreliable RPC packets.
## Playback: every remote speaker gets its own AudioStreamGenerator on a per-speaker bus
## with a low-pass filter, routed through AudioStreamPlayer3D so distance attenuation and
## stereo positioning come for free. The low-pass cutoff drops when a wall is between the
## listener and the speaker (muffled voices through walls).
##
## If no input device exists (headless CI, no microphone) the system reports itself as
## unavailable and the game falls back to text chat + pings without pretending voice works.

signal transmitting_changed(transmitting: bool)
signal input_level_changed(level: float)
signal mic_unavailable

const SAMPLE_RATE := 16000
const PACKET_MS := 40
const MAX_SPEAKERS := 4
const WALL_CUTOFF := 900.0
const OPEN_CUTOFF := 16000.0

var available := false
var transmitting := false
var ptt_held := false
var mic_device := ""

var _capture_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mix_rate := 48000
var _downsample_ratio := 3
var _speakers: Dictionary = {}   # peer_id -> {player: AudioStreamPlayer3D, playback, bus_idx}
var _speaker_buses: Array[int] = []
var _occlusion_timer := 0.0
var _input_level := 0.0


func _ready() -> void:
	_setup_buses()
	_setup_capture()
	set_process(available)


func _setup_buses() -> void:
	if AudioServer.get_bus_index("VoiceCapture") == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "VoiceCapture")
		AudioServer.set_bus_send(i, "Master")
		AudioServer.set_bus_mute(i, true)  # capture only, never audible locally
	var ci := AudioServer.get_bus_index("VoiceCapture")
	if AudioServer.get_bus_effect_count(ci) == 0:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.2
		AudioServer.add_bus_effect(ci, cap)
	for i in MAX_SPEAKERS:
		var bus_name := "VoiceOut%d" % i
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Voice")
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = OPEN_CUTOFF
			AudioServer.add_bus_effect(idx, lp)
		_speaker_buses.append(idx)


func _setup_capture() -> void:
	var devices := AudioServer.get_input_device_list()
	if devices.is_empty():
		available = false
		mic_unavailable.emit()
		return
	mic_device = str(Settings.get_value("mic_device", ""))
	if mic_device == "":
		mic_device = AudioServer.input_device if AudioServer.input_device != "" else devices[0]
	AudioServer.input_device = mic_device
	_capture_player = AudioStreamPlayer.new()
	_capture_player.name = "MicCapture"
	_capture_player.stream = AudioStreamMicrophone.new()
	_capture_player.bus = "VoiceCapture"
	_capture_player.volume_db = -80.0
	add_child(_capture_player)
	_capture_player.play()
	_mix_rate = int(AudioServer.get_mix_rate())
	_downsample_ratio = maxi(1, int(round(float(_mix_rate) / float(SAMPLE_RATE))))
	_capture = AudioServer.get_bus_effect(AudioServer.get_bus_index("VoiceCapture"), 0) as AudioEffectCapture
	available = _capture != null
	if not available:
		mic_unavailable.emit()


func is_mic_available() -> bool:
	return available


func set_ptt(held: bool) -> void:
	ptt_held = held


func _process(delta: float) -> void:
	if not available or not Net.is_online():
		return
	var want := false
	if bool(Settings.get_value("voice_enabled", true)):
		want = ptt_held if bool(Settings.get_value("voice_push_to_talk", true)) else true
	if want and not transmitting:
		transmitting = true
		transmitting_changed.emit(true)
	elif not want and transmitting:
		transmitting = false
		transmitting_changed.emit(false)
	if not transmitting:
		if _capture:
			_capture.clear_buffer()
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		return
	var buffer := _capture.get_buffer(frames)
	_input_level = 0.0
	for s in buffer:
		_input_level = maxf(_input_level, absf(s.x))
	input_level_changed.emit(_input_level)
	if _input_level < 0.006:
		return  # silence gate keeps the channel quiet and the bandwidth honest
	var pcm := PackedByteArray()
	var acc := 0.0
	var acc_n := 0
	var gain := float(Settings.get_value("mic_gain", 1.0))
	for s in buffer:
		acc += s.x
		acc_n += 1
		if acc_n >= _downsample_ratio:
			var v := clampf((acc / float(acc_n)) * gain, -1.0, 1.0)
			var iv := int(v * 32767.0)
			pcm.append(iv & 0xFF)
			pcm.append((iv >> 8) & 0xFF)
			acc = 0.0
			acc_n = 0
	if pcm.size() < 64:
		return
	var my := multiplayer.get_unique_id()
	if Net.is_host():
		_broadcast_voice(my, pcm)
	else:
		rpc_id(1, "_server_voice", pcm)


@rpc("any_peer", "call_remote", "unreliable")
func _server_voice(pcm: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	_broadcast_voice(sender, pcm)


func _broadcast_voice(speaker_id: int, pcm: PackedByteArray) -> void:
	for pid in multiplayer.get_peers():
		if pid != speaker_id:
			rpc_id(pid, "_receive_voice", speaker_id, pcm)
	# host also plays it locally
	_receive_voice(speaker_id, pcm)


@rpc("authority", "call_remote", "unreliable")
func _receive_voice(speaker_id: int, pcm: PackedByteArray) -> void:
	if not bool(Settings.get_value("voice_enabled", true)):
		return
	var speaker := _ensure_speaker(speaker_id)
	if speaker.is_empty():
		return
	var playback: AudioStreamGeneratorPlayback = speaker["playback"]
	var pb: AudioStreamPlayback = (speaker["player"] as AudioStreamPlayer3D).get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		playback = pb
	var space := playback.get_frames_available()
	var frames := pcm.size() / 2
	var count := mini(frames, space)
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		var lo := pcm[i * 2]
		var hi := pcm[i * 2 + 1]
		var v := float((hi << 8) | lo) / 32768.0
		out[i] = Vector2(v, v)
	if count > 0:
		playback.push_buffer(out)


func _ensure_speaker(peer_id: int) -> Dictionary:
	if _speakers.has(peer_id):
		return _speakers[peer_id]
	if _speakers.size() >= MAX_SPEAKERS:
		return {}
	var bus_idx: int = _speaker_buses[_speakers.size() % _speaker_buses.size()]
	var bus_name := AudioServer.get_bus_name(bus_idx)
	var p := AudioStreamPlayer3D.new()
	p.name = "Speaker%d" % peer_id
	p.bus = bus_name
	p.unit_size = 7.0
	p.max_distance = 28.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SAMPLE_RATE
	gen.buffer_length = 0.2
	p.stream = gen
	add_child(p)
	p.play()
	var playback: AudioStreamPlayback = p.get_stream_playback()
	_speakers[peer_id] = {"player": p, "playback": playback, "bus": bus_idx}
	return _speakers[peer_id]


func _physics_process(delta: float) -> void:
	_occlusion_timer -= delta
	if _occlusion_timer > 0.0:
		return
	_occlusion_timer = 0.2
	var me := Game.local_player()
	if me == null:
		return
	for pid in _speakers.keys():
		var sp: Dictionary = _speakers[pid]
		var player3d: AudioStreamPlayer3D = sp["player"]
		var speaker_player := Game.get_player(int(pid))
		if speaker_player == null:
			continue
		player3d.global_position = speaker_player.global_position + Vector3.UP * 1.5
		var bus_idx: int = sp["bus"]
		var blocked := _wall_between(me.global_position + Vector3.UP * 1.5, player3d.global_position)
		var lp := AudioServer.get_bus_effect(bus_idx, 0) as AudioEffectLowPassFilter
		if lp:
			lp.cutoff_hz = WALL_CUTOFF if blocked else OPEN_CUTOFF
		# drop speakers that left
		if not Net.players.has(int(pid)) and not Net.is_solo():
			player3d.queue_free()
			_speakers.erase(pid)


func _wall_between(a: Vector3, b: Vector3) -> bool:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = Layers.WORLD | Layers.DOOR
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


func speaker_count() -> int:
	return _speakers.size()
