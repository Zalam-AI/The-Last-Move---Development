extends Node
## Top-level orchestrator. Owns the world container, the active mission, the UI layer and
## the state machine that moves the crew between menu -> headquarters -> mission -> report.
##
## Everything that must be identical on every peer (which property, which seed, which
## modifiers) is decided by the host and broadcast; clients build the same world locally.

signal mission_built(m: MissionManager)
signal state_changed(new_state: State)

enum State { BOOT, MENU, LOBBY, HEADQUARTERS, MISSION, RESULTS }

static var instance

var state: State = State.BOOT
var mission: MissionManager = null
var headquarters: Node3D = null
var ui: UIManager
var world: Node3D
var players_root: Node3D
var is_paused := false
var last_result: Dictionary = {}
var session_seed := 0


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_tree()
	Settings.apply_all()
	Net.players_changed.connect(_on_players_changed)
	Net.session_ended.connect(_on_session_ended)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.net_error.connect(_on_net_error)
	Audio.voice_line.connect(_on_voice_line)
	ui = UIManager.new()
	ui.name = "UI"
	add_child(ui)
	go_to_menu()
	if "--mp-probe" in OS.get_cmdline_user_args():
		var probe := preload("res://scripts/core/mp_probe.gd").new()
		probe.name = "MPProbe"
		add_child(probe)


func _setup_tree() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	players_root = Node3D.new()
	players_root.name = "Players"
	world.add_child(players_root)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause") and (state == State.MISSION or state == State.HEADQUARTERS):
		toggle_pause()
	if Input.is_action_just_pressed("scoreboard") and state == State.MISSION:
		ui.set_scoreboard_visible(true)
	if Input.is_action_just_released("scoreboard") and state == State.MISSION:
		ui.set_scoreboard_visible(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Save.save_profile()
		Settings.save_settings()


# ------------------------------------------------------------------ states --

func set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func go_to_menu() -> void:
	_clear_world()
	set_state(State.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.stop_music(1.0)
	Audio.play_music("menu_corporate", 1.5)
	Audio.play_ambience("hq_lobby", 1.5, -18.0)
	ui.show_main_menu()
	if Net.is_online():
		Net.leave_session(false)


func start_solo() -> void:
	Net.start_solo()
	session_seed = randi()
	enter_headquarters()
	ui.show_lobby_panel(true)


func host_session(port: int, password: String, player_name: String) -> bool:
	Settings.set_value("player_name", player_name)
	if not Net.create_host(port, password):
		return false
	session_seed = randi()
	set_state(State.LOBBY)
	enter_headquarters()
	ui.show_lobby_panel(false)
	return true


func join_session(ip: String, port: int, password: String) -> void:
	Net.join(ip, port, password)
	set_state(State.LOBBY)
	ui.show_connecting()


func enter_headquarters() -> void:
	if not Net.is_host():
		return
	if Net.is_online():
		rpc("_rpc_enter_headquarters")
	_do_enter_headquarters()


@rpc("authority", "call_remote", "reliable")
func _rpc_enter_headquarters() -> void:
	_do_enter_headquarters()


func _do_enter_headquarters() -> void:
	_clear_world()
	mission = null
	headquarters = preload("res://scripts/levels/headquarters.gd").new()
	headquarters.name = "Headquarters"
	world.add_child(headquarters)
	set_state(State.HEADQUARTERS)
	ui.show_hud()
	ui.close_all_panels()
	Audio.play_music("hq_lobby", 2.0)
	Audio.play_ambience("hq_lobby", 2.0, -12.0)
	_spawn_players(headquarters.get_spawn_transform())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func start_mission(property_id: String, seed_override := -1, mods: Array = []) -> void:
	if not Net.is_host():
		return
	if not Save.is_property_unlocked(property_id):
		ui.notify("That contract is locked. Finish the previous property first.", "warning")
		return
	var use_seed := seed_override if seed_override >= 0 else (session_seed + hash(property_id) + randi())
	var use_mods: Array = mods
	if use_mods.is_empty():
		use_mods = _roll_modifiers(property_id, use_seed)
	if Net.is_online():
		rpc("_rpc_start_mission", property_id, use_seed, use_mods)
	_do_start_mission(property_id, use_seed, use_mods)


@rpc("authority", "call_remote", "reliable")
func _rpc_start_mission(property_id: String, use_seed: int, use_mods: Array) -> void:
	_do_start_mission(property_id, use_seed, use_mods)


func _roll_modifiers(property_id: String, use_seed: int) -> Array:
	var prop := DB.get_property(property_id)
	var pool: Array = prop.get("modifier_pool", [])
	if pool.is_empty():
		return []
	var rng := U.rng_for(use_seed)
	var out: Array = []
	var difficulty := int(prop.get("difficulty_rank", 1))
	var count := 0
	if difficulty >= 4:
		count = 1
	if difficulty >= 6:
		count = 2
	for i in count:
		var pick = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(pick):
			out.append(pick)
	return out


func _do_start_mission(property_id: String, use_seed: int, use_mods: Array) -> void:
	_clear_world()
	ui.close_all_panels()
	mission = MissionManager.new()
	mission.name = "Mission"
	mission.configure(property_id, use_seed, use_mods)
	world.add_child(mission)
	set_state(State.MISSION)
	mission.mission_ended.connect(_on_mission_ended)
	mission.notification.connect(ui.notify)
	mission.event_triggered.connect(_on_mission_event)
	ui.show_hud()
	ui.show_contract_briefing()
	_spawn_players(mission.player_spawn(0))
	if Net.is_host():
		mission.start_clock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mission_built.emit(mission)


func _on_mission_ended(result: Dictionary) -> void:
	if state == State.RESULTS:
		return
	last_result = result
	set_state(State.RESULTS)
	var payout := int(result.get("payout", 0))
	if Net.is_host():
		Save.add_credits(payout)
		Save.complete_property(str(result.get("property_id", "")), payout, _next_property_id(str(result.get("property_id", ""))))
		_award_mission_achievements(result)
	Save.bump_stat("items_delivered", int(result.get("required_delivered", 0)))
	# the campaign ends on the last property: show the epilogue instead of the report
	var final_property := _next_property_id(str(result.get("property_id", ""))) == ""
	if final_property and bool(result.get("partial", false)):
		Save.set_achievement("campaign_complete")
		if Net.is_host():
			Save.save_profile()
		ui.show_results(result)
		ui.show_epilogue(bool(result.get("success", false)))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Audio.play_music("result_sting", 0.6)
		return
	ui.show_results(result)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_music("result_sting", 0.6)


func _next_property_id(current: String) -> String:
	var props := DB.properties
	for i in props.size():
		if props[i]["id"] == current and i + 1 < props.size():
			return props[i + 1]["id"]
	return ""


func _award_mission_achievements(result: Dictionary) -> void:
	Save.set_achievement("first_day")
	if int(result.get("required_delivered", 0)) == int(result.get("required_total", -1)) and int(result.get("required_total", 0)) > 0:
		if int(result.get("property_damage", 0)) <= 0:
			Save.set_achievement("employee_month")
		if float(result.get("time_left", 0.0)) > 60.0:
			Save.set_achievement("perfect_delivery")
		if int(result.get("crew_lost", 0)) == 0:
			Save.set_achievement("nobody_left")
	if int(result.get("property_damage", 0)) >= 2000:
		Save.set_achievement("damage_specialist")
	if not result.get("unauthorised", []).is_empty():
		Save.set_achievement("not_in_contract")
	if str(result.get("property_id", "")) == "last_customer" and bool(result.get("partial", false)):
		Save.set_achievement("last_customer")


func return_to_headquarters() -> void:
	if not Net.is_host():
		return
	ui.close_all_panels()
	enter_headquarters()


func leave_to_menu() -> void:
	if Net.is_online():
		Net.disconnect_with_reason("Crew disbanded")
	_clear_world()
	go_to_menu()


func _clear_world() -> void:
	is_paused = false
	Engine.time_scale = 1.0
	for child in world.get_children():
		if child == players_root:
			continue
		world.remove_child(child)
		child.queue_free()
	for p in players_root.get_children():
		players_root.remove_child(p)
		p.queue_free()
	mission = null
	headquarters = null


# ----------------------------------------------------------------- players --

func _spawn_players(spawn: Transform3D) -> void:
	if not Net.is_host() and not Net.is_solo():
		# clients spawn their own crew nodes too, so node paths match on both sides
		pass
	var slot := 0
	for pid in Net.players.keys():
		var id := int(pid)
		if players_root.has_node(str(id)):
			slot += 1
			continue
		var p := Player.new()
		p.name = str(id)
		var offset := Vector3(cos(slot * 1.7) * 1.1, 0, sin(slot * 1.7) * 1.1)
		p.position = spawn.origin + offset
		p.rotation.y = spawn.basis.get_euler().y
		players_root.add_child(p)
		slot += 1


func _on_players_changed() -> void:
	if state == State.HEADQUARTERS or state == State.MISSION:
		var spawn := Transform3D(Basis.IDENTITY, Vector3.ZERO)
		if headquarters != null:
			spawn = headquarters.get_spawn_transform()
		elif mission != null:
			spawn = mission.player_spawn(players_root.get_child_count())
		_spawn_players(spawn)


func _on_peer_joined(id: int) -> void:
	if state == State.MISSION and Net.is_host():
		# Joining mid-contract is not supported: the crew is already inside.
		pass
	ui.notify("%s joined the crew." % Net.display_name(id), "info")


func _on_peer_left(id: int) -> void:
	# Release anything the departed player was holding so nothing floats forever.
	if mission != null:
		for f in mission.furniture:
			if is_instance_valid(f) and f.holders.has(id):
				f.release_all()
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()
	ui.notify("%s left the crew." % Net.display_name(id), "warning")


func _on_session_ended(reason: String) -> void:
	if state == State.MISSION or state == State.HEADQUARTERS or state == State.LOBBY:
		ui.notify(reason, "warning")
		go_to_menu()


func _on_net_error(message: String) -> void:
	ui.notify(message, "warning")


func _on_voice_line(text: String, seconds: float) -> void:
	ui.show_subtitle(text, seconds)


func _on_mission_event(event_name: String, _data: Dictionary) -> void:
	match event_name:
		"light_flicker":
			ui.notify("The lights disagree with you.", "spooky")
		"door_close":
			Audio.play_sfx("door_slam", Vector3.ZERO, -10.0)
		_:
			pass


func local_player() -> Player:
	return get_player(multiplayer.get_unique_id())


func get_player(id: int) -> Player:
	if players_root == null:
		return null
	return players_root.get_node_or_null(str(id)) as Player


func crew_strength() -> float:
	var s := 1.0
	if Save.owns_upgrade("gloves_grip"):
		s = 1.25
	if Save.owns_upgrade("gloves_pro"):
		s = 1.6
	if Save.owns_upgrade("straps"):
		s *= 1.15
	var alive := 1.0
	for p in players_root.get_children():
		if p is Player and not (p as Player).is_downed:
			alive = 1.0
	return s * alive


func can_players_move() -> bool:
	return (state == State.MISSION or state == State.HEADQUARTERS) and not is_paused


func report_noise(position: Vector3, amount: float) -> void:
	if mission != null and Net.is_host():
		mission.report_noise(position, amount)


func toggle_pause() -> void:
	is_paused = not is_paused
	if is_paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		ui.show_pause()
	else:
		ui.close_all_panels()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Engine.time_scale = 0.0 if is_paused and Net.is_solo() else 1.0


func buy_upgrade(id: String) -> bool:
	if Save.purchase_upgrade(id):
		ui.notify("Purchased: %s" % DB.get_upgrade(id).get("name", id), "good")
		Audio.play_sfx("purchase", Vector3.ZERO, -6.0)
		return true
	ui.notify("Insufficient credits.", "warning")
	return false


func buy_cosmetic(id: String) -> bool:
	if Save.purchase_cosmetic(id):
		ui.notify("Unlocked: %s" % DB.get_cosmetic(id).get("name", id), "good")
		return true
	return false
