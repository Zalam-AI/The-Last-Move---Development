extends Node
## Headless multiplayer probe used by tools/mp_test.sh.
##
## Runs as an autoloaded node only when --mp-probe is on the command line. It drives a
## real session (host or client) and prints machine-readable lines so that the shell
## runner can verify cross-process behaviour instead of trusting a single instance.
##
##   [MP] role=host id=1 peers=3 state=MISSION mission=willow furniture=44 loaded=0/11
##   [MP] delivery uid=12 accepted
##   [MP] remote_player peer=2 pos=(1.2,0.1,3.4) carried=-1
##   [MP] done ok=true

var role := "solo"
var mission_id := "willow"
var seed_value := 42
var port := 7777
var peer_ip := "127.0.0.1"
var run_seconds := 26.0
var property_count := 1

var _t := 0.0
var _timer := 0.0
var _started_mission := false
var _deliveries := 0
var _seen_remote := {}
var _max_peers := 0
var _loaded_reports := 0
var _last_loaded := -1
var _sync_samples := 0
var _moving_remote := false
var _prev_positions := {}
var _client_ok := false
var _saw_mission := false
var _saw_loaded := 0
var _saw_items := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = _arg_value("--mp-role", "solo")
	mission_id = _arg_value("--mp-mission", "willow")
	seed_value = int(_arg_value("--mp-seed", "42"))
	port = int(_arg_value("--mp-port", "7777"))
	peer_ip = _arg_value("--mp-ip", "127.0.0.1")
	run_seconds = float(_arg_value("--mp-seconds", "26"))
	print("[MP] boot role=%s mission=%s seed=%d port=%d" % [role, mission_id, seed_value, port])
	_start.call_deferred()


func _arg_value(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			return a.substr(key.length() + 1)
	return fallback


func _start() -> void:
	await get_tree().process_frame
	if role == "host":
		if not Game.host_session(port, "", "HOST"):
			print("[MP] done ok=false reason=host_bind_failed")
			get_tree().quit(2)
			return
	else:
		Game.join_session(peer_ip, port, "")
		Game.set_state(Game.State.LOBBY)


func _process(delta: float) -> void:
	_t += delta
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_report()
	_check()
	if _t >= run_seconds:
		_finish()


func _report() -> void:
	var m := Game.mission
	var furn := m.furniture.size() if m != null else 0
	var loaded := m.required_delivered if m != null else 0
	var total := m.required_total if m != null else 0
	var state_name := "MENU"
	match Game.state:
		Game.State.LOBBY: state_name = "LOBBY"
		Game.State.HEADQUARTERS: state_name = "HQ"
		Game.State.MISSION: state_name = "MISSION"
		Game.State.RESULTS: state_name = "RESULTS"
	_max_peers = maxi(_max_peers, Net.player_count())
	print("[MP] role=%s id=%d peers=%d max_peers=%d state=%s mission=%s furniture=%d loaded=%d/%d" % [
		role, Net.my_id(), Net.player_count(), _max_peers, state_name,
		m.property_id if m != null else "-", furn, loaded, total])


func _check() -> void:
	# host: once everyone has joined, start the contract
	if role == "host" and not _started_mission and Net.player_count() >= _expected_peers() and _t > 3.0:
		_started_mission = true
		print("[MP] host starting mission with %d peers" % Net.player_count())
		Game.start_mission(mission_id, seed_value, [])
	# host: stage a delivery so every client should see loaded/11 update
	if role == "host" and _started_mission and Game.mission != null and _deliveries < 2 and _t > 12.0:
		Game.mission.truck.set_doors(true)
		_deliver_next()
	# watch remote player movement and carried state on every peer
	for pid in Net.players.keys():
		var id := int(pid)
		if id == Net.my_id():
			continue
		var p := Game.get_player(id)
		if p == null:
			continue
		_seen_remote[id] = true
		var prev: Vector3 = _prev_positions.get(id, p.global_position)
		if p.global_position.distance_to(prev) > 0.05:
			_moving_remote = true
		_prev_positions[id] = p.global_position
	# latch what this process saw; the host may quit before we do
	if Game.mission != null:
		_saw_mission = true
		_saw_loaded = maxi(_saw_loaded, Game.mission.required_delivered)
		_saw_items = maxi(_saw_items, Game.mission.furniture.size())
	if role != "host" and _saw_mission and Net.player_count() >= 2:
		_client_ok = true


func _expected_peers() -> int:
	return int(_arg_value("--mp-expected", "1")) + 1


func _deliver_next() -> void:
	var m := Game.mission
	if m == null:
		return
	for f in m.furniture:
		if not is_instance_valid(f) or f.delivered or not f.is_required:
			continue
		var target: Vector3 = m.truck.interior_point() + Vector3(0, -0.6, 0)
		f.global_position = target
		f.linear_velocity = Vector3.ZERO
		f.angular_velocity = Vector3.ZERO
		_deliveries += 1
		print("[MP] delivery staged uid=%d item=%s" % [f.uid, f.item_id])
		return


func _finish() -> void:
	var ok := true
	var reasons: Array[String] = []
	if _max_peers < _expected_peers():
		ok = false
		reasons.append("only %d/%d peers connected" % [_max_peers, _expected_peers()])
	if role == "host":
		if not _saw_mission:
			ok = false
			reasons.append("host never built a mission")
		else:
			if _saw_loaded <= 0:
				ok = false
				reasons.append("host saw no deliveries")
	else:
		if not _client_ok:
			ok = false
			reasons.append("client never saw the mission")
		if _saw_loaded <= 0:
			ok = false
			reasons.append("client never saw a delivery")
		if not _moving_remote:
			ok = false
			reasons.append("client never saw another player move")
		if _saw_items < 10:
			ok = false
			reasons.append("client built too little furniture")
	print("[MP] summary role=%s peers=%d max_peers=%d remote=%d moving_remote=%s loaded=%d furniture=%d" % [
		role, _max_peers, _max_peers, _seen_remote.size(), str(_moving_remote), _saw_loaded, _saw_items])
	print("[MP] done ok=%s %s" % [str(ok), "" if reasons.is_empty() else "reasons=" + ", ".join(reasons)])
	get_tree().quit(0 if ok else 3)
