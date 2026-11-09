class_name Player
extends CharacterBody3D
## First-person mover.
##
## Owns movement, camera comfort, interaction probing, grab/release/rotate/throw
## requests, health & reviving, footsteps and its replicated state.
## Movement is client-authoritative (each peer owns its own body); furniture physics is
## host-authoritative, so grab/rotate/throw are *requests* forwarded to the host.

signal downed_changed(is_downed: bool)
signal health_changed(hp: float)
signal prompt_changed(text: String, sub: String)
signal carry_changed(object: Furniture)

const WALK_SPEED := 3.15
const SPRINT_SPEED := 5.25
const CROUCH_SPEED := 1.65
const ACCEL := 11.0
const AIR_ACCEL := 2.2
const JUMP_VELOCITY := 5.15
const MOUSE_SENS := 0.0022
const INTERACT_DIST := 2.9
const REVIVE_TIME := 2.2
const BLEEDOUT_TIME := 75.0
const SYNC_HZ := 18.0

var peer_id := 1
var is_local := false
var display_name := "Mover"

var head: Node3D
var camera: Camera3D
var interact_ray: RayCast3D
var flashlight: SpotLight3D
var body_model: PlayerModel
var hands: Node3D
var voice: Node

var health := 100.0
var stamina := 100.0
var is_downed := false
var bleedout := 0.0
var revive_progress := 0.0
var carried: Furniture = null
var crouching := false
var sprinting := false
var has_flashlight := true

var prompt_text := ""
var prompt_sub := ""
var _focused: Node = null
var _pitch := 0.0
var _bob_phase := 0.0
var _shake := 0.0
var _shake_offset := Vector3.ZERO
var _sync_timer := 0.0
var _sync_target := Vector3.ZERO
var _sync_speed := 0.0
var _sync_flags := 0
var _footstep_timer := 0.0
var _crouch_height := 1.8
var _standing_head := 1.52
var _carry_slot := 0
var _emote_time := 0.0


func _ready() -> void:
	var desired := int(name) if name.is_valid_int() else 1
	peer_id = desired
	set_multiplayer_authority(peer_id)
	is_local = peer_id == multiplayer.get_unique_id()
	collision_layer = Layers.PLAYER
	collision_mask = Layers.PLAYER_MASK
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	_build_nodes()
	display_name = Net.display_name(peer_id)
	if is_local:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		if camera:
			camera.current = false
		if body_model:
			body_model.visible = true
		if hands:
			hands.visible = false
	if body_model:
		body_model.visible = not is_local


func _build_nodes() -> void:
	var col := get_node_or_null("Collision")
	if col == null:
		col = CollisionShape3D.new()
		col.name = "Collision"
		add_child(col)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)

	head = get_node_or_null("Head")
	if head == null:
		head = Node3D.new()
		head.name = "Head"
		head.position = Vector3(0, _standing_head, 0)
		add_child(head)
	camera = head.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.fov = float(Settings.get_value("fov", 85.0))
		camera.near = 0.05
		camera.far = 220.0
		head.add_child(camera)
	interact_ray = head.get_node_or_null("InteractRay") as RayCast3D
	if interact_ray == null:
		interact_ray = RayCast3D.new()
		interact_ray.name = "InteractRay"
		interact_ray.target_position = Vector3(0, 0, -INTERACT_DIST)
		interact_ray.collision_mask = Layers.WORLD | Layers.FURNITURE | Layers.DOOR | Layers.CREATURE | Layers.INTERACT
		interact_ray.collide_with_areas = true
		interact_ray.collide_with_bodies = true
		head.add_child(interact_ray)
	flashlight = head.get_node_or_null("Flashlight") as SpotLight3D
	if flashlight == null:
		flashlight = SpotLight3D.new()
		flashlight.name = "Flashlight"
		flashlight.light_energy = 3.2
		flashlight.light_color = Color(1.0, 0.95, 0.85)
		flashlight.spot_range = 18.0
		flashlight.spot_angle = 34.0
		flashlight.spot_attenuation = 1.4
		flashlight.shadow_enabled = false
		flashlight.position = Vector3(0.14, -0.12, 0)
		head.add_child(flashlight)
	flashlight.visible = false
	_apply_flashlight_upgrade()

	body_model = get_node_or_null("Body") as PlayerModel
	if body_model == null:
		body_model = PlayerModel.new()
		body_model.name = "Body"
		add_child(body_model)
	body_model.setup(Save.equipped())

	hands = get_node_or_null("Hands")
	if hands == null:
		hands = Node3D.new()
		hands.name = "Hands"
		hands.position = Vector3(0, -0.32, -0.5)
		camera.add_child(hands)
		var hb := MeshBuilder.new()
		hb.box(Vector3(0.14, 0.1, 0.3), Vector3(-0.22, 0, 0), Save.cosmetic_color("gloves", Color("#4a4a52")))
		hb.box(Vector3(0.14, 0.1, 0.3), Vector3(0.22, 0, 0), Save.cosmetic_color("gloves", Color("#4a4a52")))
		hb.box(Vector3(0.13, 0.12, 0.28), Vector3(-0.22, -0.02, 0.1), Color("#3d4450"))
		hb.box(Vector3(0.13, 0.12, 0.28), Vector3(0.22, -0.02, 0.1), Color("#3d4450"))
		var mi := MeshInstance3D.new()
		mi.mesh = hb.build_mesh()
		hands.add_child(mi)

	voice = Net.voice
	if is_local and voice != null:
		pass


func _enter_tree() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if Game.state != Game.State.MISSION and Game.state != Game.State.HEADQUARTERS:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE_SENS * float(Settings.get_value("sensitivity", 1.0))
		rotate_y(-event.relative.x * sens)
		var inv: float = -1.0 if bool(Settings.get_value("invert_y", false)) else 1.0
		_pitch = clampf(_pitch - event.relative.y * sens * inv, deg_to_rad(-88), deg_to_rad(88))
		head.rotation.x = _pitch
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()


# ---------------------------------------------------------------- physics ---

func _physics_process(delta: float) -> void:
	if is_local:
		_local_physics(delta)
	else:
		_remote_physics(delta)
	_animate(delta)


func _local_physics(delta: float) -> void:
	var can_move := Game.can_players_move() and not is_downed
	var input_dir := Vector2.ZERO
	if can_move:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# crouch with ceiling check
	var want_crouch := can_move and Input.is_action_pressed("crouch")
	if want_crouch != crouching:
		if not want_crouch and _blocked_above():
			want_crouch = true
		crouching = want_crouch
		_apply_crouch()

	sprinting = can_move and Input.is_action_pressed("sprint") and not crouching and input_dir.length() > 0.1 and stamina > 1.0
	if sprinting:
		stamina = maxf(0.0, stamina - 17.0 * delta)
	else:
		stamina = minf(100.0, stamina + 13.0 * delta)

	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	speed *= _carry_speed_multiplier()
	speed *= _water_speed_multiplier()

	var wish := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized() * speed
	var accel := ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, wish.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, wish.z, accel * speed * delta)

	if is_on_floor():
		if can_move and Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = JUMP_VELOCITY
			Audio.play_sfx("player_jump", global_position, -10.0)
	else:
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 14.0)) * delta

	var was_on_floor := is_on_floor()
	move_and_slide()
	if not was_on_floor and is_on_floor() and velocity.y < -3.0:
		Audio.play_sfx("player_land", global_position, clampf(-4.0 + velocity.y, -20.0, 0.0))
		add_shake(clampf(absf(velocity.y) * 0.012, 0.0, 0.09))
		if velocity.y < -13.0:
			take_damage(absf(velocity.y) * 2.2, "fell")

	_footsteps(delta, Vector2(velocity.x, velocity.z).length())
	_stranded_check()
	_interaction_scan()
	_handle_actions(delta)
	if carried != null and not is_instance_valid(carried):
		carried = null
	if carried != null and not carried.holders.has(peer_id):
		carried = null
		carry_changed.emit(null)
	_sync_timer += delta
	if _sync_timer >= 1.0 / SYNC_HZ:
		_sync_timer = 0.0
		_send_state()

	if is_downed:
		bleedout -= delta
		if bleedout <= 0.0:
			_go_missing()


func _remote_physics(delta: float) -> void:
	global_position = global_position.lerp(_sync_target, clampf(delta * 11.0, 0.0, 1.0))
	crouching = (_sync_flags & 1) != 0
	is_downed = (_sync_flags & 2) != 0


func _apply_crouch() -> void:
	var col := get_node_or_null("Collision") as CollisionShape3D
	var target_h := 1.2 if crouching else 1.8
	if col and col.shape is CapsuleShape3D:
		var cap := col.shape as CapsuleShape3D
		cap.height = target_h
		col.position.y = target_h * 0.5
	_crouch_height = target_h
	var target_head := 0.92 if crouching else _standing_head
	var tw := create_tween()
	tw.tween_property(head, "position:y", target_head, 0.12)


func _blocked_above() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.1, global_position + Vector3.UP * 1.95)
	q.collision_mask = Layers.WORLD
	var hit := space.intersect_ray(q)
	return not hit.is_empty()


func _carry_speed_multiplier() -> float:
	if carried == null:
		return 1.0
	var w := clampf(carried.weight / 130.0, 0.0, 1.0)
	var base := lerpf(1.0, 0.42, w)
	if carried.holders.size() < carried.min_carriers:
		base *= 0.72
	if Save.owns_upgrade("dolly"):
		base = minf(1.0, base * 1.18)
	if Save.owns_upgrade("straps") and carried.holders.size() < carried.min_carriers:
		base *= 1.15
	return base


func _water_speed_multiplier() -> float:
	if Game.mission == null:
		return 1.0
	var depth := Game.mission.water_height - global_position.y
	if depth <= 0.35:
		return 1.0
	var t := clampf((depth - 0.35) / 0.9, 0.0, 1.0)
	if crouching:
		t = minf(1.0, t + 0.2)
	return lerpf(1.0, 0.52, t)


func _footsteps(delta: float, speed: float) -> void:
	if not is_on_floor() or speed < 0.4:
		_footstep_timer = 0.0
		return
	_footstep_timer -= delta * speed
	if _footstep_timer <= 0.0:
		_footstep_timer = 2.4 if not crouching else 3.4
		var base := "foot_step"
		if crouching:
			base = "foot_crouch"
		elif sprinting:
			base = "foot_run"
		Audio.play_sfx(base, global_position, -12.0 if crouching else -6.0, randf_range(0.92, 1.08))
		Game.report_noise(global_position, 0.35 if sprinting else (0.12 if crouching else 0.22))


func _stranded_check() -> void:
	if global_position.y < -18.0 and not is_downed:
		take_damage(200.0, "void")


# ------------------------------------------------------------ interaction ---

func _interaction_scan() -> void:
	_focused = null
	prompt_text = ""
	prompt_sub = ""
	if interact_ray == null or not interact_ray.is_colliding():
		_set_prompt("", "")
		return
	var target := interact_ray.get_collider()
	if carried != null:
		_set_prompt("Release %s" % carried.data.get("name", "object"), "[E]  •  [Q]/[R] rotate  •  [G] throw")
		return
	if target is Furniture:
		var f := target as Furniture
		_highlight_only(f)
		if f.delivered:
			_set_prompt("%s  •  already loaded" % f.data.get("name", "Object"), "")
			return
		var carriers_needed := f.min_carriers
		var crew := f.holders.size()
		var sub := "[E] grab"
		if carriers_needed > 1:
			sub = "[E] grab  •  %d/%d movers (%s)" % [crew, carriers_needed, "heavier than you" if crew + 1 < carriers_needed else "ready"]
		_set_prompt(str(f.data.get("name", "Object")), sub)
		_focused = f
		return
	if target is Interactable:
		var it := target as Interactable
		_set_prompt(it.prompt_title, it.prompt_sub)
		_focused = it
		return
	if target is Player and (target as Player).is_downed and target != self:
		_set_prompt("Revive %s" % (target as Player).display_name, "[E] hold")
		_focused = target
		return
	if target is Door:
		var d := target as Door
		_set_prompt(d.display_label, "[E] %s" % ("close" if d.is_open else "open"))
		_focused = d
		return
	if target is RigidBody3D:
		var rb := target as RigidBody3D
		if rb.has_method("interact"):
			_set_prompt("Interact", "[E]")
			_focused = rb
		return


func _highlight_only(f: Furniture) -> void:
	if Game.mission == null:
		return
	Game.mission.highlight_furniture(f)


func _set_prompt(t: String, sub: String) -> void:
	if prompt_text != t or prompt_sub != sub:
		prompt_text = t
		prompt_sub = sub
		prompt_changed.emit(t, sub)


func _handle_actions(delta: float) -> void:
	if is_downed:
		return
	if Input.is_action_just_pressed("interact"):
		if carried != null:
			_request_release()
		elif _focused is Furniture:
			_request_grab(_focused as Furniture)
		elif _focused is Door:
			(_focused as Door).toggle()
		elif _focused is Interactable:
			(_focused as Interactable).activate(self)
		elif _focused is Player:
			# revive handled below (hold)
			pass
	if Input.is_action_pressed("interact") and _focused is Player and (_focused as Player).is_downed:
		var t := _focused as Player
		t.revive_progress += delta
		if t.revive_progress >= revive_time():
			_revive(t)
	if Input.is_action_just_released("interact"):
		if _focused is Player:
			(_focused as Player).revive_progress = 0.0
	if carried != null:
		if Input.is_action_just_pressed("rotate_left"):
			_request_rotate(1.0)
		if Input.is_action_just_pressed("rotate_right"):
			_request_rotate(-1.0)
		if Input.is_action_just_pressed("throw"):
			_request_throw()


func _revive(target: Player) -> void:
	if target == null:
		return
	target.revive_progress = 0.0
	if Net.is_host():
		target.rpc("_do_revive")
	else:
		target.rpc_id(1, "_server_revive", peer_id)
	Audio.play_sfx("revive", target.global_position, -4.0)
	Save.bump_stat("revives", 1)


@rpc("any_peer", "call_local", "reliable")
func _server_revive(by_id: int) -> void:
	if not Net.is_host():
		return
	rpc("_do_revive")
	_do_revive()


## Field Medkit upgrade: faster hands and a better patch job.
func revive_time() -> float:
	return 1.4 if Save.owns_upgrade("medkit") else REVIVE_TIME


func revived_health() -> float:
	return 75.0 if Save.owns_upgrade("medkit") else 45.0


@rpc("authority", "call_remote", "reliable")
func _do_revive() -> void:
	is_downed = false
	Save.set_achievement("occupational_hazard")
	health = revived_health()
	bleedout = 0.0
	health_changed.emit(health)
	downed_changed.emit(false)


# ---------------------------------------------------------------- grabbing --

func _request_grab(f: Furniture) -> void:
	if f == null or not is_instance_valid(f):
		return
	if Net.is_host():
		_do_grab(f)
	else:
		rpc_id(1, "_server_grab", f.uid)


@rpc("any_peer", "call_remote", "reliable")
func _server_grab(fuid: int) -> void:
	if not Net.is_host():
		return
	var mission := Game.mission
	if mission == null:
		return
	var f := mission.furniture_by_uid(fuid)
	if f == null:
		return
	if global_position.distance_to(f.global_position) > INTERACT_DIST + 2.0:
		return
	if f.grab(peer_id):
		rpc("_do_grab_client", fuid)
		_do_grab_client(fuid)


@rpc("authority", "call_remote", "reliable")
func _do_grab_client(fuid: int) -> void:
	var mission := Game.mission
	if mission == null:
		return
	var f := mission.furniture_by_uid(fuid)
	if f == null:
		return
	carried = f
	carry_changed.emit(f)
	Audio.play_sfx("grab", f.global_position, -6.0)


func _do_grab(f: Furniture) -> void:
	if f.grab(peer_id):
		carried = f
		carry_changed.emit(f)
		Audio.play_sfx("grab", f.global_position, -6.0)
		if not Net.is_online():
			return
		rpc("_do_grab_client", f.uid)


## Called by the host when something takes what this player is holding.
func force_drop() -> void:
	if carried == null:
		return
	if is_local:
		_request_release()
		return
	# host acting on a remote player's proxy node
	var f := carried
	carried = null
	carry_changed.emit(null)
	if is_instance_valid(f):
		f.release(peer_id)
	rpc("_rpc_force_drop")


@rpc("authority", "call_remote", "reliable")
func _rpc_force_drop() -> void:
	if carried != null:
		carried = null
		carry_changed.emit(null)
		Audio.play_sfx("grab", global_position, -6.0)


func _request_release() -> void:
	if carried == null:
		return
	var f := carried
	carried = null
	carry_changed.emit(null)
	if Net.is_host():
		f.release(peer_id)
	else:
		rpc_id(1, "_server_release", f.uid)


@rpc("any_peer", "call_remote", "reliable")
func _server_release(fuid: int) -> void:
	var mission := Game.mission
	if mission == null:
		return
	var f := mission.furniture_by_uid(fuid)
	if f:
		f.release(peer_id)


func _request_rotate(dir: float) -> void:
	if carried == null:
		return
	if Net.is_host():
		carried.apply_torque_impulse(Vector3.UP * dir * carried.mass * 0.55)
	else:
		rpc_id(1, "_server_rotate", carried.uid, dir)


@rpc("any_peer", "call_remote", "reliable")
func _server_rotate(fuid: int, dir: float) -> void:
	var mission := Game.mission
	if mission == null:
		return
	var f := mission.furniture_by_uid(fuid)
	if f and f.holders.has(peer_id):
		f.apply_torque_impulse(Vector3.UP * dir * f.mass * 0.55)


func _request_throw() -> void:
	if carried == null:
		return
	var f := carried
	carried = null
	carry_changed.emit(null)
	var dir := -camera.global_transform.basis.z
	if Net.is_host():
		_do_throw(f, dir)
	else:
		rpc_id(1, "_server_throw", f.uid, dir)


func _do_throw(f: Furniture, dir: Vector3) -> void:
	f.release_all()
	f.apply_central_impulse((dir + Vector3.UP * 0.35).normalized() * f.mass * 4.2)
	f.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * f.mass * 0.4)


@rpc("any_peer", "call_remote", "reliable")
func _server_throw(fuid: int, dir: Vector3) -> void:
	var mission := Game.mission
	if mission == null:
		return
	var f := mission.furniture_by_uid(fuid)
	if f:
		_do_throw(f, dir)


# ------------------------------------------------------------------ health --

func take_damage(amount: float, source := "") -> void:
	if is_downed or Game.state == Game.State.MISSION and Game.mission == null:
		return
	if Save.owns_upgrade("helmet"):
		amount *= 0.65
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	add_shake(clampf(amount * 0.01, 0.02, 0.25))
	Audio.play_sfx("player_hurt", global_position, -4.0)
	if health <= 0.0:
		_go_down(source)


func _go_down(_source: String) -> void:
	if is_downed:
		return
	is_downed = true
	bleedout = BLEEDOUT_TIME
	if carried != null:
		_request_release()
	downed_changed.emit(true)
	Save.bump_stat("deaths", 1)
	if Game.mission:
		Game.mission.on_player_downed(self)


func _go_missing() -> void:
	# Company policy: an employee who does not return is not "dead", they are "missing".
	var mission := Game.mission
	if mission != null:
		mission.on_player_missing(self)
	respawn_at_truck()


func respawn_at_truck() -> void:
	var mission := Game.mission
	if mission == null:
		return
	is_downed = false
	health = 55.0
	bleedout = 0.0
	health_changed.emit(health)
	downed_changed.emit(false)
	global_position = mission.truck_spawn_point()
	velocity = Vector3.ZERO


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)
	health_changed.emit(health)


## Company Flashlight upgrade: a longer, tighter, brighter beam - the reliable deterrent.
func _apply_flashlight_upgrade() -> void:
	if flashlight == null or not Save.owns_upgrade("flashlight"):
		return
	flashlight.light_energy = 4.6
	flashlight.spot_range = 26.0
	flashlight.spot_angle = 30.0


func toggle_flashlight() -> void:
	flashlight.visible = not flashlight.visible
	Audio.play_sfx("click", global_position, -14.0)


func add_shake(amount: float) -> void:
	_shake = minf(0.5, _shake + amount * float(Settings.get_value("camera_shake", 1.0)))


# ------------------------------------------------------------- presentation --

func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if is_local else _sync_speed
	if body_model != null and body_model.visible:
		body_model.animate(delta, speed, crouching, carried != null, is_on_floor(), is_downed)
	# camera comfort: head bob + sway, both scale with settings
	if is_local and camera != null:
		var bob_amount := float(Settings.get_value("head_bob", 1.0))
		var sway := float(Settings.get_value("view_sway", 1.0))
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		_bob_phase += delta * (5.0 + ground_speed * 2.4)
		var bob_y := sin(_bob_phase * 2.0) * 0.021 * clampf(ground_speed / 4.0, 0.0, 1.3) * bob_amount
		var bob_x := sin(_bob_phase) * 0.017 * clampf(ground_speed / 4.0, 0.0, 1.3) * bob_amount
		_shake = maxf(0.0, _shake - delta * 0.9)
		_shake_offset = Vector3(
			randf_range(-1, 1) * _shake * 0.35,
			randf_range(-1, 1) * _shake * 0.35,
			0) if _shake > 0.001 else _shake_offset.lerp(Vector3.ZERO, 0.2)
		camera.position = Vector3(bob_x, bob_y, 0) + _shake_offset
		camera.rotation.z = -bob_x * 0.35 * sway
		if hands:
			var target_y := -0.32
			var target_z := -0.5
			if carried != null:
				target_y = -0.18 - clampf(carried.size.y * 0.12, 0.0, 0.25)
				target_z = -0.62
			if _emote_time > 0.0:
				_emote_time -= delta
				target_y += sin(_emote_time * 22.0) * 0.12
			hands.position.y = U.damp(hands.position.y, target_y, 10.0, delta)
			hands.position.z = U.damp(hands.position.z, target_z, 10.0, delta)


func _send_state() -> void:
	_sync_flags = 0
	if crouching:
		_sync_flags |= 1
	if is_downed:
		_sync_flags |= 2
	if carried != null:
		_sync_flags |= 4
	if is_on_floor():
		_sync_flags |= 8
	if _emote_time > 0.0:
		_sync_flags |= 16
	if not Net.is_online():
		return
	rpc("_net_state", global_position, rotation.y, _pitch, _sync_flags,
		Vector2(velocity.x, velocity.z).length(), display_name)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, yaw: float, pitch: float, flags: int, speed: float, pname: String) -> void:
	_sync_target = pos
	rotation.y = yaw
	_pitch = pitch
	if head:
		head.rotation.x = pitch
	_sync_flags = flags
	_sync_speed = speed
	crouching = (flags & 1) != 0
	is_downed = (flags & 2) != 0
	display_name = pname


func play_emote() -> void:
	_emote_time = 1.2
	Audio.play_sfx("emote", global_position, -8.0)
