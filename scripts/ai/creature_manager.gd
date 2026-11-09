class_name CreatureManager
extends Node3D
## Directs the supernatural layer of a mission.
##
## The director keeps the pressure *uneven*: long silences, then a creature appears
## behind the crew; a doll shows up in a doorway that was empty; the thing that was
## carrying the piano is now standing in the truck bay. It never spawns anything within
## sight of a player, and it never spawns more than the property's danger budget.
##
## Host-only simulation. Clients receive spawn/despawn RPCs and per-creature state.

signal creature_spawned(c: Creature)
signal creature_left(c: Creature)
signal director_message(text: String, kind: String)
signal item_stolen(f: Furniture)
signal crew_hit(c: Creature, p: Player)

const SPAWN_MIN_DIST := 16.0
const SPAWN_MAX_DIST := 34.0
const MAX_ALIVE := 3
const FIRST_SPAWN_DELAY := 55.0

var mission: MissionManager
var creatures: Array[Creature] = []
var danger_rank := 1
var seed_value := 0
var enabled := true

var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _spawn_timer := FIRST_SPAWN_DELAY
var _pressure := 0.0
var _pending_despawn: Array[Creature] = []
var _calm_timer := 0.0
var _spawned_total := 0
var _banished := 0
var _stolen_items: Array[String] = []
var _last_kinds: Array[int] = []


func configure(p_mission: MissionManager, p_danger: int, p_seed: int) -> void:
	mission = p_mission
	danger_rank = clampf(p_danger, 1, 8)
	seed_value = p_seed
	_rng.seed = hash("%d:%d:creatures" % [p_seed, p_danger])
	_spawn_timer = FIRST_SPAWN_DELAY - float(danger_rank) * 3.0


func _ready() -> void:
	name = "Creatures"


func budget() -> int:
	# how many creatures a property can have alive at once
	return clampi(1 + int((danger_rank - 1) / 2.5), 1, MAX_ALIVE)


func available_kinds() -> Array[int]:
	var kinds: Array[int] = [Creature.Kind.TENANT, Creature.Kind.DOLL]
	if danger_rank >= 2:
		kinds.append(Creature.Kind.BREATHER)
	if danger_rank >= 3:
		kinds.append(Creature.Kind.BELLHOP)
	return kinds


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not enabled:
		return
	if mission == null or mission.state == MissionManager.MState.ENDED:
		return
	_cleanup()
	_pressure = maxf(0.0, _pressure - delta * 0.02)
	_calm_timer = maxf(0.0, _calm_timer - delta)
	if _calm_timer > 0.0:
		return
	_spawn_timer -= delta * (1.0 + _pressure * 0.35)
	if _spawn_timer > 0.0:
		return
	if creatures.size() >= budget():
		_spawn_timer = _rng.randf_range(18.0, 34.0)
		return
	_spawn_timer = _rng.randf_range(38.0, 72.0) - float(danger_rank) * 2.0
	spawn_one()


func _cleanup() -> void:
	for i in range(creatures.size() - 1, -1, -1):
		if not is_instance_valid(creatures[i]):
			creatures.remove_at(i)


func spawn_one(kind_override := -1) -> Creature:
	if not Net.is_host():
		return null
	var kinds := available_kinds()
	var kind := kind_override
	if kind < 0:
		kind = kinds[_rng.randi_range(0, kinds.size() - 1)]
		# avoid repeating the same creature three times in a row
		if _last_kinds.size() >= 2 and _last_kinds[_last_kinds.size() - 1] == kind and _last_kinds[_last_kinds.size() - 2] == kind:
			kind = kinds[_rng.randi_range(0, kinds.size() - 1)]
	_last_kinds.append(kind)
	if _last_kinds.size() > 4:
		_last_kinds.remove_at(0)
	var pos := _pick_spawn_point()
	if pos == Vector3.INF:
		return null
	var c := Creature.new()
	c.setup(kind, _next_id, self)
	c.global_position = pos
	add_child(c)
	c.state = Creature.CState.ROAM
	creatures.append(c)
	_spawned_total += 1
	creature_spawned.emit(c)
	if Net.is_online():
		rpc("_rpc_spawn", _next_id, kind, pos)
	_next_id += 1
	_announce(c)
	return c


func _announce(c: Creature) -> void:
	var text := ""
	match c.kind:
		Creature.Kind.TENANT:
			text = "Something in this house is standing very still and waiting for you to be alone."
		Creature.Kind.DOLL:
			text = "You have not moved that doll. Somebody has."
		Creature.Kind.BREATHER:
			text = "The walls are breathing. Make less noise."
		Creature.Kind.BELLHOP:
			text = "Something in a uniform wants what you are carrying."
	director_message.emit(text, "spooky")


func _pick_spawn_point() -> Vector3:
	var crew: Array[Player] = []
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		if p != null and is_instance_valid(p):
			crew.append(p)
	if crew.is_empty():
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var best := Vector3.INF
	var best_score := -1.0
	for i in 18:
		var origin := crew[_rng.randi_range(0, crew.size() - 1)].global_position
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
		var cand := origin + Vector3(cos(ang), 0, sin(ang)) * dist
		var q := PhysicsRayQueryParameters3D.create(cand + Vector3(0, 5.0, 0), cand + Vector3(0, -4.0, 0), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var floor_pos: Vector3 = (hit["position"] as Vector3) + Vector3(0, 0.08, 0)
		# must be well away from the whole crew, and not inside a wall
		var min_d := 999.0
		for p in crew:
			min_d = minf(min_d, p.global_position.distance_to(floor_pos))
		if min_d < SPAWN_MIN_DIST * 0.75:
			continue
		var probe := PhysicsShapeQueryParameters3D.new()
		var sh := CapsuleShape3D.new()
		sh.radius = 0.45
		sh.height = 1.6
		probe.shape = sh
		probe.transform = Transform3D(Basis.IDENTITY, floor_pos + Vector3(0, 0.9, 0))
		probe.collision_mask = Layers.WORLD
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		var score := min_d
		if score > best_score:
			best_score = score
			best = floor_pos
	return best


# --------------------------------------------------------------- director input ---

## Called by the mission when a loud noise happens: creatures get curious.
func on_noise(pos: Vector3, amount: float) -> void:
	if not Net.is_host():
		return
	_pressure = minf(1.5, _pressure + amount * 0.3)
	for c in creatures:
		if not is_instance_valid(c):
			continue
		if c.global_position.distance_to(pos) < c.hearing_range:
			# everything in earshot wanders over to look
			c.home = pos
			if c.kind == Creature.Kind.BREATHER:
				c.move_speed = maxf(c.move_speed, 2.2)


## Called when a player has been downed by something else (falling furniture, water):
## the director backs off so the crew is not punished twice.
func on_crew_hurt() -> void:
	_calm_timer = maxf(_calm_timer, 12.0)


func on_progress(fraction: float) -> void:
	# the closer the crew is to finishing, the more it wants to interfere
	_pressure = clampf(_pressure + fraction * 0.35, 0.0, 2.0)
	if fraction > 0.6 and _rng.randf() < 0.5:
		_spawn_timer = minf(_spawn_timer, _rng.randf_range(6.0, 14.0))


## Force a specific creature (used by property scripts for scripted beats).
func force_spawn(kind: int) -> Creature:
	return spawn_one(kind)


func banish_all() -> void:
	for c in creatures.duplicate():
		if is_instance_valid(c):
			c.banish()


# ------------------------------------------------------------- creature events ---

func on_creature_contact(c: Creature, p: Player) -> void:
	crew_hit.emit(c, p)
	_pressure = maxf(0.0, _pressure - 0.1)


func on_creature_hit(c: Creature, hits: int) -> void:
	if hits == 1:
		director_message.emit("You hit it. It noticed.", "info")


func on_creature_banished(c: Creature) -> void:
	_banished += 1
	director_message.emit("It has gone back to where it came from.", "info")
	if mission:
		mission.creatures_banished = _banished


func on_creature_despawned(c: Creature) -> void:
	creatures.erase(c)
	creature_left.emit(c)


func on_creature_took_item(c: Creature, f: Furniture) -> void:
	director_message.emit("%s has taken the %s. Get it back before it reaches the dark." % [c.kind_name(), _item_name(f)], "warning")


func on_creature_stole_item(c: Creature, f: Furniture) -> void:
	if mission == null or not is_instance_valid(f):
		return
	var label := _item_name(f)
	_stolen_items.append(label)
	item_stolen.emit(f)
	mission.on_furniture_stolen(f)
	director_message.emit("%s is gone. It is in the house now." % label.capitalize(), "warning")


func _item_name(f: Furniture) -> String:
	if f == null or not is_instance_valid(f):
		return "item"
	return str(f.data.get("name", f.item_id))


# ------------------------------------------------------------------- queries ---

func alive_count() -> int:
	return creatures.size()


func nearest_creature(pos: Vector3) -> Creature:
	var best: Creature = null
	var best_d := 999.0
	for c in creatures:
		if not is_instance_valid(c):
			continue
		var d := c.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best


func danger_hint() -> String:
	var c := nearest_creature(Vector3.ZERO)
	if c == null:
		return ""
	return c.kind_name()


func stolen_items() -> Array[String]:
	return _stolen_items


# ------------------------------------------------------------------- network ---

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(p_id: int, p_kind: int, p_pos: Vector3) -> void:
	var c := Creature.new()
	c.setup(p_kind, p_id, self)
	c.global_position = p_pos
	add_child(c)
	creatures.append(c)
	creature_spawned.emit(c)
	_announce(c)
	_next_id = maxi(_next_id, p_id + 1)
