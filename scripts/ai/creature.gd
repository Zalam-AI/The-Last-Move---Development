class_name Creature
extends CharacterBody3D
## A supernatural agent. Host-simulated, client-interpolated.
##
## Creatures do not fight the crew, they inconvenience it: they stand in doorways,
## they take things, they make you drop what you are carrying. The crew's counterplay is
## light, silence, numbers, and a well-aimed chair.
##
## Every creature is banished by three solid hits from moving furniture. It is never
## killed -- it is asked to leave.

enum Kind { TENANT, DOLL, BREATHER, BELLHOP }
enum CState { DORMANT, ROAM, STALK, ATTACK, STUN, RETREAT }

const KIND_DATA := {
	Kind.TENANT: {
		"name": "THE TENANT",
		"speed": 2.65, "chase": 3.45, "sight": 26.0, "hearing": 18.0,
		"damage": 17.0, "interval": 1.5, "reach": 2.0, "light_fear": 1.0,
		"voice": "tenant", "height": 2.05,
	},
	Kind.DOLL: {
		"name": "THE DOLL",
		"speed": 0.0, "chase": 4.6, "sight": 30.0, "hearing": 8.0,
		"damage": 12.0, "interval": 2.4, "reach": 1.5, "light_fear": 0.0,
		"voice": "doll", "height": 0.95,
	},
	Kind.BREATHER: {
		"name": "THE BREATHER",
		"speed": 1.9, "chase": 3.15, "sight": 0.0, "hearing": 34.0,
		"damage": 24.0, "interval": 1.9, "reach": 2.1, "light_fear": 0.0,
		"voice": "breather", "height": 2.3,
	},
	Kind.BELLHOP: {
		"name": "THE BELLHOP",
		"speed": 2.2, "chase": 3.6, "sight": 22.0, "hearing": 12.0,
		"damage": 6.0, "interval": 3.0, "reach": 2.2, "light_fear": 0.3,
		"voice": "bellhop", "height": 1.85,
	},
}

const SYNC_HZ := 12.0
const GRAVITY := 14.0
const BANISH_HITS := 3

var cid := 0
var kind := Kind.TENANT
var state := CState.DORMANT
var manager: Node = null
var target: Player = null
var home := Vector3.ZERO
var move_speed := 2.6
var chase_speed := 3.4
var sight_range := 24.0
var hearing_range := 18.0
var attack_damage := 18.0
var attack_interval := 1.5
var attack_reach := 2.0
var light_fear := 1.0

var life := 0.0
var max_life := 150.0
var hits_taken := 0

var _attack_cd := 0.0
var _roam_target := Vector3.ZERO
var _roam_timer := 0.0
var _lost_timer := 0.0
var _stun := 0.0
var _sync_timer := 0.0
var _voice_timer := 0.0
var _lunge := 0.0
var _steal_target: Furniture = null
var _steal_point := Vector3.ZERO
var _steal_progress := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_state := 0
var _seen_timer := 0.0
var _doll_relocate_cd := 0.0

var rng := RandomNumberGenerator.new()
var model: Node3D
var _eye_light: OmniLight3D
var _spine: Node3D
var _limbs: Array[Node3D] = []
var _phase := 0.0
var _rig: Dictionary = {}          # pivot name -> Node3D, for the walk cycle
var _clip := ""

var space_state: PhysicsDirectSpaceState3D


# --------------------------------------------------------------- lifecycle ---

func setup(p_kind: int, p_id: int, p_manager: Node) -> void:
	kind = p_kind
	cid = p_id
	manager = p_manager
	name = "Creature%d" % cid
	var d: Dictionary = KIND_DATA[kind]
	move_speed = float(d["speed"])
	chase_speed = float(d["chase"])
	sight_range = float(d["sight"])
	hearing_range = float(d["hearing"])
	attack_damage = float(d["damage"])
	attack_interval = float(d["interval"])
	attack_reach = float(d["reach"])
	light_fear = float(d["light_fear"])
	_clip = str(d["voice"])
	rng.seed = hash("%d:%d" % [cid, kind])
	collision_layer = Layers.CREATURE
	collision_mask = Layers.CREATURE_MASK
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(52.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = maxf(1.0, float(d["height"]))
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	add_child(cs)
	_build_model()
	home = global_position
	_roam_target = home


func _ready() -> void:
	_net_pos = global_position
	_net_yaw = rotation.y
	_lost_timer = 5.0
	if kind == Kind.DOLL:
		# dolls arrive already sitting somewhere, pretending to be furniture
		state = CState.DORMANT
		_voice_timer = rng.randf_range(6.0, 18.0)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		_apply_remote(delta)
		return
	life += delta
	space_state = get_world_3d().direct_space_state
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_stun = maxf(0.0, _stun - delta)
	_voice_timer -= delta
	_doll_relocate_cd = maxf(0.0, _doll_relocate_cd - delta)
	_lunge = maxf(0.0, _lunge - delta * 2.2)
	if _stun > 0.0:
		state = CState.STUN
		velocity = velocity.lerp(Vector3.ZERO, delta * 6.0)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		_sync(delta)
		return
	match kind:
		Kind.TENANT:
			_think_tenant(delta)
		Kind.DOLL:
			_think_doll(delta)
		Kind.BREATHER:
			_think_breather(delta)
		Kind.BELLHOP:
			_think_bellhop(delta)
	_check_thrown_furniture()
	_check_despawn(delta)
	_sync(delta)


func _check_despawn(_delta: float) -> void:
	if Game.mission == null:
		queue_free()
		return
	var far := true
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		if p and p.global_position.distance_to(global_position) < 62.0:
			far = false
			break
	if far and life > 20.0:
		despawn()


# ------------------------------------------------------------------ senses ---

func _players() -> Array[Player]:
	var out: Array[Player] = []
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		if p != null and is_instance_valid(p):
			out.append(p)
	return out


func _los(from: Vector3, to: Vector3) -> bool:
	if space_state == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.DOOR)
	q.exclude = [get_rid()]
	return space_state.intersect_ray(q).is_empty()


func _nearest_visible(max_dist: float) -> Player:
	if sight_range <= 0.01:
		return null
	var best: Player = null
	var best_d := max_dist
	var eye := global_position + Vector3(0, 1.5, 0)
	for p in _players():
		if p.is_downed:
			continue
		var d := global_position.distance_to(p.global_position)
		if d > minf(max_dist, sight_range):
			continue
		if d > 6.0 and not _los(eye, p.global_position + Vector3(0, 1.2, 0)):
			continue
		if d < best_d:
			best_d = d
			best = p
	return best


func _is_lit(p: Player) -> bool:
	if p == null or p.flashlight == null or not p.flashlight.visible:
		return false
	var fl := p.flashlight
	var to_me := (global_position + Vector3(0, 1.2, 0)) - fl.global_position
	if to_me.length() > 19.0:
		return false
	var fwd := -fl.global_transform.basis.z
	return fwd.dot(to_me.normalized()) > 0.93


func _crew_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for p in _players():
		if not p.is_downed and p.global_position.distance_to(pos) < radius:
			n += 1
	return n


func _is_observed() -> bool:
	# "watched" means: inside any player's view cone with clear line of sight
	for p in _players():
		if p.is_downed or p.camera == null:
			continue
		var to_me := (global_position + Vector3(0, 0.6, 0)) - p.camera.global_position
		var dist := to_me.length()
		if dist > 34.0:
			continue
		var fwd := -p.camera.global_transform.basis.z
		if fwd.dot(to_me.normalized()) < 0.62:
			continue
		if _los(p.camera.global_position, global_position + Vector3(0, 0.6, 0)):
			return true
	return false


# ------------------------------------------------------------------- brains ---

func _think_tenant(delta: float) -> void:
	var p := _nearest_visible(34.0)
	if p != null and _is_lit(p):
		# light is the only thing it respects
		state = CState.RETREAT
		var away := (global_position - p.global_position).normalized()
		_move(away, move_speed * 1.15, delta)
		_set_glow(0.2)
		if _voice_timer <= 0.0:
			_voice_timer = rng.randf_range(4.0, 8.0)
			Audio.play_sfx("creature_shriek", global_position, -9.0)
		return
	_set_glow(1.0)
	if p != null:
		# a lone mover is a target; a crew of three is a deterrent
		var crew := _crew_near(global_position, 9.0)
		if crew >= 3 and rng.randf() < 0.02:
			state = CState.RETREAT
			_move((global_position - p.global_position).normalized(), move_speed, delta)
			return
		target = p
		var d := global_position.distance_to(p.global_position)
		if d <= attack_reach + 0.3:
			state = CState.ATTACK
			velocity.x = lerpf(velocity.x, 0.0, delta * 8.0)
			velocity.z = lerpf(velocity.z, 0.0, delta * 8.0)
			velocity.y -= GRAVITY * delta
			move_and_slide()
			_do_attack(p)
			_lost_timer = 0.0
			return
		state = CState.STALK
		_move((p.global_position - global_position).normalized(), chase_speed, delta)
		_lost_timer = 0.0
		if _voice_timer <= 0.0:
			_voice_timer = rng.randf_range(7.0, 15.0)
			Audio.play_sfx("creature_growl", global_position, -8.0)
		return
	_lost_timer += delta
	if _lost_timer > 4.0:
		_roam(delta, 12.0)


func _think_doll(delta: float) -> void:
	# It is only ever still while you are looking at it.
	if _is_observed():
		state = CState.DORMANT
		velocity = velocity.lerp(Vector3.ZERO, delta * 9.0)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		_seen_timer = 0.0
		return
	_seen_timer += delta
	var p := _nearest_visible(40.0)
	if p == null:
		if _seen_timer > 3.0:
			_doll_relocate()
		return
	if _is_lit(p) and light_fear > 0.0:
		state = CState.RETREAT
		_move((global_position - p.global_position).normalized(), chase_speed * 0.8, delta)
		return
	var d := global_position.distance_to(p.global_position)
	if d <= attack_reach:
		state = CState.ATTACK
		_do_attack(p)
		if _doll_relocate_cd <= 0.0:
			_doll_relocate_cd = rng.randf_range(5.0, 9.0)
			_doll_relocate()
		return
	state = CState.STALK
	_move((p.global_position - global_position).normalized(), chase_speed, delta)
	if rng.randf() < delta * 0.35:
		Audio.play_sfx("doll_move", global_position, -10.0)


func _doll_relocate() -> void:
	if Game.mission == null:
		return
	var best := global_position
	var best_score := -1.0
	for i in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(6.0, 20.0)
		var cand := global_position + Vector3(cos(ang), 0, sin(ang)) * dist
		var ok := true
		for p in _players():
			if p.global_position.distance_to(cand) < 4.0:
				ok = false
				break
		if not ok:
			continue
		var ground: Variant = _ground_below(cand)
		if ground == null:
			continue
		var ground_pos := ground as Vector3
		var score := rng.randf()
		if score > best_score:
			best_score = score
			best = ground_pos
	if best != global_position:
		global_position = best
		velocity = Vector3.ZERO
		Audio.play_sfx("doll_move", best, -8.0)


func _ground_below(at: Vector3) -> Variant:
	if space_state == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 6.0, 0), at + Vector3(0, -3.0, 0), Layers.WORLD)
	var hit := space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3) + Vector3(0, 0.05, 0)


func _think_breather(delta: float) -> void:
	# blind: it only knows where noise came from
	var m := Game.mission
	var noisy := m != null and m.noise_level > 0.12
	if noisy:
		var noise_pos := home
		if m != null and m.noise_level > 0.12:
			noise_pos = m.noise_position
		for p in _players():
			if p.velocity.length() > 1.4:
				noise_pos = p.global_position
				break
		state = CState.STALK
		_move((noise_pos - global_position).normalized(), chase_speed, delta)
		_lost_timer = 0.0
		if _voice_timer <= 0.0:
			_voice_timer = rng.randf_range(2.5, 5.0)
			Audio.play_sfx("creature_breath", global_position, -7.0)
		# contact damage even though it cannot see
		for p in _players():
			if not p.is_downed and global_position.distance_to(p.global_position) < attack_reach and _attack_cd <= 0.0:
				state = CState.ATTACK
				_do_attack(p)
		return
	_lost_timer += delta
	if _lost_timer > 1.5:
		_roam(delta, 4.0)
		if _voice_timer <= 0.0:
			_voice_timer = rng.randf_range(3.0, 6.0)
			Audio.play_sfx("creature_breath", global_position, -12.0)


func _think_bellhop(delta: float) -> void:
	# it wants what you are carrying, not you
	if _steal_target != null and (not is_instance_valid(_steal_target) or _steal_target.delivered):
		_steal_target = null
	if _steal_target == null:
		_steal_target = _find_carried_furniture()
		if _steal_target != null:
			_steal_point = _pick_steal_point()
			_steal_progress = 0.0
			Audio.play_sfx("creature_growl", global_position, -6.0)
	if _steal_target == null:
		var p := _nearest_visible(26.0)
		if p != null and global_position.distance_to(p.global_position) > 3.0:
			state = CState.STALK
			_move((p.global_position - global_position).normalized(), move_speed, delta)
			return
		_roam(delta, 10.0)
		return
	state = CState.STALK
	var item_pos := _steal_target.global_position
	var d := global_position.distance_to(item_pos)
	if not _steal_target.get_meta("being_stolen", false):
		# close in, then take it
		if d > 1.9:
			_move((item_pos - global_position).normalized(), chase_speed, delta)
			return
		_take_furniture(_steal_target)
		return
	# dragging it off into the dark
	_drag_furniture(delta)


func _find_carried_furniture() -> Furniture:
	var best: Furniture = null
	var best_d := 26.0
	for p in _players():
		if p.is_downed or p.carried == null or not is_instance_valid(p.carried):
			continue
		var d := global_position.distance_to(p.carried.global_position)
		if d < best_d:
			best_d = d
			best = p.carried
	return best


func _pick_steal_point() -> Vector3:
	# the furthest reachable corner from the crew within 30 m
	var crew := _players()
	var origin := global_position
	var best := origin
	var best_score := -1.0
	for i in 10:
		var ang := rng.randf() * TAU
		var cand := origin + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(12.0, 26.0)
		var ground: Variant = _ground_below(cand)
		if ground == null:
			continue
		var ground_pos := ground as Vector3
		var nearest := 999.0
		for p in crew:
			nearest = minf(nearest, p.global_position.distance_to(ground_pos))
		if nearest > best_score:
			best_score = nearest
			best = ground_pos
	return best


func _take_furniture(f: Furniture) -> void:
	f.set_meta("being_stolen", true)
	if is_instance_valid(f):
		f.release_all()
		f.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		f.freeze = true
	Audio.play_sfx("creature_growl", f.global_position, -4.0)
	for p in _players():
		if p.carried == f:
			p.force_drop()
	if manager and manager.has_method("on_creature_took_item"):
		manager.on_creature_took_item(self, f)


func _drag_furniture(delta: float) -> void:
	var f := _steal_target
	if f == null or not is_instance_valid(f):
		_steal_target = null
		return
	var to_point := _steal_point - f.global_position
	to_point.y = 0.0
	if to_point.length() < 2.2:
		Audio.play_sfx("whisper", f.global_position, -6.0)
		if manager and manager.has_method("on_creature_stole_item"):
			manager.on_creature_stole_item(self, f)
		_steal_target = null
		state = CState.RETREAT
		despawn_delayed(1.5)
		return
	f.global_position = f.global_position + to_point.normalized() * 2.1 * delta
	global_position = global_position.lerp(f.global_position + Vector3(0, 0, 0), delta * 3.5)
	global_position.y = f.global_position.y
	Audio.play_scrape(f.material_kind, f.global_position, 0.4)
	var d := f.global_position.distance_to(global_position)
	if d > 4.0:
		global_position = f.global_position - to_point.normalized() * 1.6


func _roam(delta: float, radius: float) -> void:
	state = CState.ROAM
	_roam_timer -= delta
	if _roam_timer <= 0.0 or global_position.distance_to(_roam_target) < 1.2:
		_roam_timer = rng.randf_range(4.0, 9.0)
		var ang := rng.randf() * TAU
		_roam_target = home + Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(2.0, radius)
	_move((_roam_target - global_position).normalized(), move_speed * 0.55, delta)


# ------------------------------------------------------------------ actions ---

func _move(dir: Vector3, spd: float, delta: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.05:
		velocity.x = lerpf(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 8.0)
	else:
		dir = dir.normalized()
		var d := _steer(dir)
		velocity.x = d.x * spd
		velocity.z = d.z * spd
		var face := atan2(d.x, d.z)
		rotation.y = lerp_angle(rotation.y, face, delta * 6.0)
	velocity.y -= GRAVITY * delta
	if is_on_floor():
		velocity.y = maxf(velocity.y, -0.5)
	move_and_slide()
	_phase += delta * (2.5 + velocity.length() * 1.4)
	_animate()


## Simple wall-following steering: probe ahead, then 35 and 70 degrees either side.
func _steer(dir: Vector3) -> Vector3:
	var eye := global_position + Vector3(0, 0.9, 0)
	if not _blocked(eye, dir, 1.7):
		return dir
	for angle in [0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var cand := dir.rotated(Vector3.UP, angle)
		if not _blocked(eye, cand, 1.7):
			return cand
	# boxed in: stop and reconsider next frame
	return Vector3.ZERO


func _blocked(from: Vector3, dir: Vector3, dist: float) -> bool:
	if space_state == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist, Layers.WORLD | Layers.DOOR)
	q.exclude = [get_rid()]
	return not space_state.intersect_ray(q).is_empty()


func _do_attack(p: Player) -> void:
	if _attack_cd > 0.0 or p == null or p.is_downed:
		return
	_attack_cd = attack_interval
	_lunge = 1.0
	p.take_damage(attack_damage, str(KIND_DATA[kind]["name"]))
	Audio.play_sfx("creature_shriek" if kind != Kind.BREATHER else "creature_breath", global_position, -3.0)
	if manager != null and manager.has_method("on_creature_contact"):
		manager.on_creature_contact(self, p)


func _check_thrown_furniture() -> void:
	# a thrown chair is the crew's only real weapon
	for f in _mission_furniture():
		if f.linear_velocity.length() < 4.2:
			continue
		if f.global_position.distance_to(global_position + Vector3(0, 0.8, 0)) > 2.2:
			continue
		take_hit(f.linear_velocity.normalized())
		return


func _mission_furniture() -> Array[Furniture]:
	if Game.mission == null:
		return []
	return Game.mission.furniture


func take_hit(dir: Vector3) -> void:
	if _stun > 0.4:
		return
	hits_taken += 1
	_stun = 1.6
	velocity = (dir + Vector3(0, 0.6, 0)).normalized() * 4.5
	Audio.play_sfx("creature_shriek", global_position, -2.0)
	if manager != null and manager.has_method("on_creature_hit"):
		manager.on_creature_hit(self, hits_taken)
	if hits_taken >= BANISH_HITS:
		banish()


func banish() -> void:
	if manager != null and manager.has_method("on_creature_banished"):
		manager.on_creature_banished(self)
	Audio.play_sfx("whisper", global_position, 0.0)
	despawn_delayed(0.6)


func despawn_delayed(seconds: float) -> void:
	var t := get_tree().create_timer(seconds)
	t.timeout.connect(despawn)


func despawn() -> void:
	if manager != null and manager.has_method("on_creature_despawned"):
		manager.on_creature_despawned(self)
	if Net.is_online():
		rpc("_rpc_despawn")
	queue_free()


# ------------------------------------------------------------------- network ---

func _sync(delta: float) -> void:
	_sync_timer += delta
	if _sync_timer < 1.0 / SYNC_HZ:
		return
	_sync_timer = 0.0
	if not Net.is_online():
		return
	rpc("_rpc_state", global_position, rotation.y, int(state), _lunge, bool(_steal_target != null))


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_state(pos: Vector3, yaw: float, st: int, lunge: float, stealing: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_state = st
	_lunge = lunge
	if stealing and _steal_target == null and Game.mission != null:
		for f in Game.mission.furniture:
			if is_instance_valid(f) and f.global_position.distance_to(pos) < 4.0:
				_steal_target = f
				break


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn() -> void:
	queue_free()


func _apply_remote(delta: float) -> void:
	global_position = global_position.lerp(_net_pos, minf(1.0, delta * 12.0))
	rotation.y = lerp_angle(rotation.y, _net_yaw, minf(1.0, delta * 10.0))
	_phase += delta * 3.0
	_animate()


# -------------------------------------------------------------------- visuals ---

func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var b := MeshBuilder.new()
	match kind:
		Kind.TENANT:
			_build_tenant(b)
		Kind.DOLL:
			_build_doll(b)
		Kind.BREATHER:
			_build_breather(b)
		Kind.BELLHOP:
			_build_bellhop(b)
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	model.add_child(mi)
	if kind != Kind.DOLL:
		_eye_light = OmniLight3D.new()
		_eye_light.light_color = Color(0.9, 0.85, 0.7) if kind == Kind.TENANT else Color(0.6, 0.8, 1.0)
		_eye_light.light_energy = 0.35
		_eye_light.omni_range = 2.4
		_eye_light.position = Vector3(0, 1.7, 0.2) if kind != Kind.DOLL else Vector3.ZERO
		model.add_child(_eye_light)
	_spine = model


func _build_tenant(b: MeshBuilder) -> void:
	var dark := Color("#14141a")
	var coat := Color("#1d1f28")
	b.cyl(0.19, 0.34, 1.15, Vector3(0, 1.02, 0), coat, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 8)
	b.box(Vector3(0.44, 0.5, 0.26), Vector3(0, 1.62, 0), coat)
	_add_limb("arm_l", Vector3(0.1, 0.34, 0.1), Vector3(-0.24, 1.37, 0.02), dark)
	_add_limb("arm_r", Vector3(0.1, 0.34, 0.1), Vector3(0.24, 1.37, 0.02), dark)
	b.sphere(0.15, Vector3(0, 1.98, 0), Color("#d8d2c4"), MeshBuilder.Mat.PLAIN, false, 0.28)
	b.sphere(0.028, Vector3(-0.055, 2.0, 0.12), Color(1.0, 0.9, 0.6), MeshBuilder.Mat.EMISSIVE, false)
	b.sphere(0.028, Vector3(0.055, 2.0, 0.12), Color(1.0, 0.9, 0.6), MeshBuilder.Mat.EMISSIVE, false)
	b.box(Vector3(0.1, 0.02, 0.04), Vector3(0, 1.9, 0.14), dark)  # mouth line
	# long legs, hinged at the hip so they can actually walk
	_add_limb("leg_l", Vector3(0.13, 0.9, 0.13), Vector3(-0.11, 0.9, 0), dark)
	_add_limb("leg_r", Vector3(0.13, 0.9, 0.13), Vector3(0.11, 0.9, 0), dark)


func _build_doll(b: MeshBuilder) -> void:
	var dress := Color("#7a2f36")
	var skin := Color("#e6d3c0")
	b.cyl(0.3, 0.42, 0.5, Vector3(0, 0.3, 0), dress, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 10)  # skirt
	b.box(Vector3(0.28, 0.28, 0.18), Vector3(0, 0.66, 0), dress)   # torso
	b.sphere(0.16, Vector3(0, 0.86, 0), skin, MeshBuilder.Mat.PLAIN, false, 0.32)  # head
	b.sphere(0.02, Vector3(-0.055, 0.88, 0.13), Color.BLACK, MeshBuilder.Mat.PLAIN, false)
	b.sphere(0.02, Vector3(0.055, 0.88, 0.13), Color.BLACK, MeshBuilder.Mat.PLAIN, false)
	b.box(Vector3(0.06, 0.01, 0.01), Vector3(0, 0.8, 0.15), Color("#8a2a2a"))
	b.box(Vector3(0.07, 0.3, 0.07), Vector3(-0.18, 0.6, 0.02), skin)   # arms
	b.box(Vector3(0.07, 0.3, 0.07), Vector3(0.18, 0.6, 0.02), skin)
	b.box(Vector3(0.09, 0.2, 0.09), Vector3(-0.09, 0.1, 0), skin)      # legs
	b.box(Vector3(0.09, 0.2, 0.09), Vector3(0.09, 0.1, 0), skin)
	b.box(Vector3(0.26, 0.03, 0.2), Vector3(0, 0.98, -0.02), Color("#3a2a24"))  # bonnet


func _build_breather(b: MeshBuilder) -> void:
	var flesh := Color("#6b3a3a")
	var bone := Color("#c8bda8")
	# a tall, featureless thing with a rib cage that opens when it inhales
	b.cyl(0.28, 0.5, 1.5, Vector3(0, 0.85, 0), flesh, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 9)
	for i in 5:
		var r := 0.34 + 0.06 * float(i % 2)
		b.cyl(r, r, 0.09, Vector3(0, 1.15 + i * 0.22, 0), bone, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 9)
	b.sphere(0.2, Vector3(0, 1.78, 0), flesh, MeshBuilder.Mat.PLAIN, false, 0.4)
	b.box(Vector3(0.16, 0.1, 0.06), Vector3(0, 1.74, 0.18), Color("#1a0e0e"))  # mouth
	b.cyl(0.5, 0.75, 0.5, Vector3(0, 0.25, 0), flesh, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 9)


func _build_bellhop(b: MeshBuilder) -> void:
	var uni := Color("#5a2a34")
	var trim := Color("#c8a24a")
	b.cyl(0.28, 0.4, 0.9, Vector3(0, 0.45, 0), uni, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 10)
	b.box(Vector3(0.42, 0.5, 0.26), Vector3(0, 1.2, 0), uni)
	b.box(Vector3(0.44, 0.06, 0.28), Vector3(0, 1.0, 0), trim)
	b.sphere(0.15, Vector3(0, 1.58, 0), Color("#cfc0aa"), MeshBuilder.Mat.PLAIN, false, 0.3)
	b.cyl(0.17, 0.17, 0.1, Vector3(0, 1.7, 0), uni, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 10)  # pillbox cap
	b.box(Vector3(0.3, 0.03, 0.2), Vector3(0, 1.65, 0.06), uni)
	_add_limb("arm_l", Vector3(0.1, 0.55, 0.1), Vector3(-0.28, 1.475, 0), uni)
	_add_limb("arm_r", Vector3(0.1, 0.55, 0.1), Vector3(0.28, 1.475, 0), uni)


func _add_limb(pivot_name: String, size: Vector3, pivot_pos: Vector3, color: Color) -> void:
	# Each limb is its own mesh under a pivot node at the joint, so the walk cycle can
	# swing it. The body stays one merged mesh; only the limbs cost a draw call each.
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = pivot_pos
	var lm := MeshBuilder.new()
	lm.box(size, Vector3(0, -size.y * 0.5, 0), color)
	var mi := MeshInstance3D.new()
	mi.mesh = lm.build_mesh()
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	pivot.add_child(mi)
	model.add_child(pivot)
	_rig[pivot_name] = pivot


func _set_glow(v: float) -> void:
	if _eye_light != null:
		_eye_light.light_energy = 0.15 + v * 0.5


func _animate() -> void:
	if _spine == null:
		return
	var bob := sin(_phase * 2.2) * 0.045
	_spine.position.y = bob
	_spine.rotation.z = sin(_phase) * 0.05
	if _lunge > 0.01:
		_spine.rotation.x = -_lunge * 0.35
	else:
		_spine.rotation.x = lerpf(_spine.rotation.x, 0.0, 0.2)
	if _rig.is_empty():
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(planar / 2.6, 0.0, 1.0)
	var swing := sin(_phase) * (0.08 + 0.5 * amp)
	var leg_l: Node3D = _rig.get("leg_l")
	var leg_r: Node3D = _rig.get("leg_r")
	if leg_l != null:
		leg_l.rotation.x = swing
	if leg_r != null:
		leg_r.rotation.x = -swing
	# arms counter-swing while walking and come up when the thing commits to a lunge
	var arm := -swing * 0.75
	if _lunge > 0.01:
		arm = lerpf(arm, -1.3, clampf(_lunge, 0.0, 1.0))
	var arm_l: Node3D = _rig.get("arm_l")
	var arm_r: Node3D = _rig.get("arm_r")
	if arm_l != null:
		arm_l.rotation.x = arm
	if arm_r != null:
		arm_r.rotation.x = arm * 0.82


func kind_name() -> String:
	return str(KIND_DATA[kind]["name"])
