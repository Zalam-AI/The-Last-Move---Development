class_name MissionManager
extends Node3D
## The mission runtime: contract generation, furniture spawning, the clock, scoring,
## supernatural event scheduling, delivery validation and host->client state replication.
##
## Determinism: every peer builds the same property and the same furniture from
## (property_id, seed). Node paths therefore match across peers, which is what makes
## per-object RPCs and batched state replication possible without spawner plumbing.

signal timer_changed(time_left: float, total: float)
signal contract_updated
signal objective_changed
signal mission_ended(result: Dictionary)
signal event_triggered(event_name: String, data: Dictionary)
signal notification(text: String, kind: String)
signal muster_warning(away_names: Array)

enum MState { BUILDING, ACTIVE, OVERDUE, ENDED }

const SYNC_HZ := 14.0
const MAX_SYNC_OBJECTS := 26
const SYNC_RADIUS := 48.0

var property_id := "willow"
var seed_value := 0
var modifiers: Array[String] = []
var state: MState = MState.BUILDING

var property: PropertyBase
var truck: Truck
var players_root: Node3D
var furniture: Array[Furniture] = []
var _furn_by_uid: Dictionary = {}
var contract: Dictionary = {}
var time_total := 780.0
var time_left := 780.0
var required_total := 0
var required_delivered := 0
var optional_total := 0
var optional_delivered := 0
var property_damage := 0.0
var crew_lost := 0
const MUSTER_RADIUS := 14.0

var crew_downed := 0
var unauthorised_loaded: Array[String] = []
var alive_players: Dictionary = {}
var events_fired: Array[String] = []
var noise_level := 0.0
var noise_position := Vector3.ZERO
var water_height := -1000.0
var creatures: CreatureManager = null
var hints: HintDirector = null
var creatures_banished := 0
var modifier_effects: Dictionary = {}
var equipment_losses := 0.0
var required_destroyed := 0
var extra_item_spawned := false

var _rng := RandomNumberGenerator.new()
var _sync_timer := 0.0
var _event_timer := 60.0
var _noise_decay := 0.0
var _reported_end := false
var _highlight_target: Furniture = null


## Reads the `effects` block of every active modifier once, so gameplay code asks for a
## named effect instead of hard-coding modifier ids in five places.
func _collect_modifier_effects() -> void:
	modifier_effects.clear()
	for m in modifiers:
		var md := DB.get_modifier(m)
		if md.is_empty():
			continue
		var fx: Dictionary = md.get("effects", {})
		for key in fx.keys():
			modifier_effects[str(key)] = float(fx[key])


func effect(key: String, fallback := 1.0) -> float:
	return float(modifier_effects.get(key, fallback))


func has_effect(key: String) -> bool:
	return modifier_effects.has(key)


func configure(p_property_id: String, p_seed: int, p_modifiers: Array) -> void:
	property_id = p_property_id
	seed_value = p_seed
	modifiers.clear()
	for m in p_modifiers:
		modifiers.append(str(m))
	_rng.seed = hash("%s:%d" % [property_id, seed_value])
	_collect_modifier_effects()


func _ready() -> void:
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	_build_property()
	_generate_contract()
	_spawn_furniture()
	_spawn_truck()
	_spawn_creatures()
	hints = HintDirector.new()
	hints.name = "HintDirector"
	add_child(hints)
	hints.setup(self)
	if Net.is_host():
		state = MState.ACTIVE
	time_left = time_total
	timer_changed.emit(time_left, time_total)
	Game.mission_built.emit(self)


# ------------------------------------------------------------------ build ---

func _build_property() -> void:
	var prop_def := DB.get_property(property_id)
	var script_path: String = prop_def.get("layout", "")
	var script_res := load(script_path)
	if script_res == null:
		push_error("Missing property layout: %s" % script_path)
		return
	property = script_res.new()
	property.name = "Property"
	add_child(property)
	property.setup(self, prop_def, _rng)
	if has_effect("dark"):
		_apply_darkness()
	time_total = float(prop_def.get("deadline", 780))
	for m in modifiers:
		var md := DB.get_modifier(m)
		time_total *= float(md.get("time_mult", 1.0))


## "Night Shift": kill most of the lighting budget. The crew's flashlights become the
## primary light source, which changes how every other system reads.
func _apply_darkness() -> void:
	var dim := 0.42
	var stack: Array[Node] = [property]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is OmniLight3D:
			var l := n as OmniLight3D
			l.light_energy *= dim
			l.omni_range *= 0.8
		for c in n.get_children():
			stack.append(c)


func _generate_contract() -> void:
	var prop_def := DB.get_property(property_id)
	contract = {
		"property_id": property_id,
		"title": prop_def.get("title", "Property"),
		"code": prop_def.get("code", "PROPERTY"),
		"subtitle": prop_def.get("subtitle", ""),
		"briefing": prop_def.get("briefing", ""),
		"notes": prop_def.get("notes", []),
		"seed": seed_value,
		"required": [],
		"optional": [],
		"modifiers": [],
		"story_index": int(prop_def.get("index", 1)) - 1,
	}
	for m in modifiers:
		var md := DB.get_modifier(m)
		if not md.is_empty():
			contract["modifiers"].append({"id": m, "name": md.get("name", m), "desc": md.get("desc", "")})
	var note_rng := RandomNumberGenerator.new()
	note_rng.seed = hash(seed_value)
	var notes: Array = contract["notes"]
	if not notes.is_empty():
		var pool: Array = DB.flavor.get("contract_random_notes", [])
		if not pool.is_empty():
			contract["extra_note"] = pool[note_rng.randi_range(0, pool.size() - 1)]
	contract_updated.emit()


func _spawn_furniture() -> void:
	var idx := 0
	for spawn in property.spawns:
		var candidates: Array = spawn.get("candidates", [])
		if candidates.is_empty():
			continue
		var required := bool(spawn.get("required", false))
		var chance := float(spawn.get("chance", 1.0))
		if not required and _rng.randf() > chance:
			continue
		var item_id: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var f := _create_furniture(item_id, idx, spawn)
		if f == null:
			continue
		idx += 1
		var entry := {
			"uid": f.uid,
			"item_id": item_id,
			"name": DB.get_item(item_id).get("name", item_id),
			"room": spawn.get("room", ""),
			"value": DB.item_value(item_id),
		}
		if required:
			f.is_required = true
			f.fragility = minf(0.95, f.fragility * effect("fragility_mult", 1.0))
			f.contract_uid = "req_%d" % f.uid
			contract["required"].append(entry)
			required_total += 1
		elif bool(spawn.get("contract_optional", false)):
			f.is_optional = true
			f.contract_uid = "opt_%d" % f.uid
			contract["optional"].append(entry)
			optional_total += 1
		if spawn.has("damage"):
			f.take_damage(float(spawn["damage"]), false)
	# "One Last Item" modifier: an extra valuable object appears mid-mission.
	if has_effect("extra_item"):
		contract["extra_item_pending"] = true
	contract_updated.emit()


func _create_furniture(item_id: String, uid: int, spawn: Dictionary) -> Furniture:
	var f := Furniture.new()
	f.setup(item_id, uid)
	var xf: Transform3D = spawn.get("xf", Transform3D(Basis.IDENTITY, spawn.get("pos", Vector3.ZERO)))
	if spawn.has("rot"):
		xf.basis = Basis(Vector3.UP, float(spawn["rot"]))
	f.global_transform = xf
	f.damaged.connect(_on_furniture_damaged.bind(f))
	f.picked_up.connect(_on_furniture_picked_up)
	f.dropped.connect(_on_furniture_dropped)
	f.delivered_state_changed.connect(_on_furniture_delivered)
	add_child(f)
	furniture.append(f)
	_furn_by_uid[f.uid] = f
	return f


func _spawn_truck() -> void:
	truck = Truck.new()
	truck.name = "Truck"
	var cap := Truck.BASE_CAPACITY + (4 if Save.owns_upgrade("truck_capacity") else 0)
	truck.setup(cap, Save.owns_upgrade("truck_light"))
	truck.global_transform = property.truck_transform
	add_child(truck)
	truck.furniture_loaded.connect(_on_furniture_loaded)
	truck.capacity_warning.connect(_on_capacity_warning)


func _spawn_creatures() -> void:
	creatures = CreatureManager.new()
	creatures.name = "CreatureDirector"
	var prop_def := DB.get_property(property_id)
	var danger := int(prop_def.get("difficulty_rank", 1))
	creatures.configure(self, danger, seed_value)
	add_child(creatures)
	creatures.director_message.connect(func(text, kind): notification.emit(text, kind))
	creatures.crew_hit.connect(func(c, p): _on_creature_hit_crew(c, p))
	creatures.item_stolen.connect(func(f): _on_creature_stole_item(f))
	if not Net.is_host():
		creatures.enabled = false


func _on_creature_hit_crew(c: Creature, p: Player) -> void:
	notification.emit("%s hit %s." % [c.kind_name(), p.display_name], "warning")
	crew_downed = 0
	for pid in Net.players.keys():
		var other := Game.get_player(int(pid))
		if other != null and other.is_downed:
			crew_downed += 1


func _on_creature_stole_item(f: Furniture) -> void:
	property_damage += float(f.base_value) * 0.5
	contract_updated.emit()


## A creature dragged a contracted object into the dark. It is gone from the job.
func on_furniture_stolen(f: Furniture) -> void:
	if f == null or not is_instance_valid(f):
		return
	_furn_by_uid.erase(f.uid)
	furniture.erase(f)
	if f.is_required:
		notification.emit("CONTRACTED ITEM LOST: %s" % str(f.data.get("name", "Object")), "warning")
	f.queue_free()
	contract_updated.emit()


# -------------------------------------------------------------- lifecycle ---

func start_clock() -> void:
	state = MState.ACTIVE
	time_left = time_total
	_rng.seed = hash("%s:%d:events" % [property_id, seed_value])
	_event_timer = _rng.randf_range(45.0, 80.0)
	if property:
		property.on_mission_start(self)
	timer_changed.emit(time_left, time_total)


func _process(delta: float) -> void:
	if state == MState.ACTIVE or state == MState.OVERDUE:
		if Net.is_host():
			_tick_clock(delta)
		_noise_decay = maxf(0.0, _noise_decay - delta * 0.55)
		noise_level = _noise_decay
	if property:
		property.mission_tick(self, delta)
	if Net.is_host():
		_network_tick(delta)


func _tick_clock(delta: float) -> void:
	if state == MState.ACTIVE:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			state = MState.OVERDUE
			notification.emit("DEADLINE MISSED. Leave the property. Now.", "warning")
			if Net.is_online():
				rpc("_rpc_clock", time_left, int(state))
		timer_changed.emit(time_left, time_total)
	if state == MState.OVERDUE:
		time_left -= delta  # counts up as overtime (negative)
		timer_changed.emit(time_left, time_total)


## Called when the contract is more than a third done: "One Last Item" drops one more
## valuable object into the property, and the crew has to go back for it.
func _maybe_spawn_extra_item() -> void:
	if extra_item_spawned or not has_effect("extra_item") or property == null:
		return
	if required_total <= 0:
		return
	if float(required_delivered) / float(required_total) < 0.34:
		return
	extra_item_spawned = true
	var pool := ["gramophone", "painting_framed", "mirror_cursed", "container_strange", "mirror_tall"]
	var item_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	var spots: Array = property.spawns
	var spot: Dictionary = {}
	if not spots.is_empty():
		spot = spots[_rng.randi_range(0, spots.size() - 1)]
	var f := _create_furniture(item_id, 9000 + _rng.randi_range(0, 900), spot)
	if f == null:
		return
	f.is_required = true
	f.contract_uid = "req_%d" % f.uid
	required_total += 1
	contract["required"].append({
		"uid": f.uid,
		"item_id": item_id,
		"name": DB.get_item(item_id).get("name", item_id),
		"room": spot.get("room", "unknown"),
		"value": DB.item_value(item_id),
	})
	notification.emit("ONE LAST ITEM: the customer remembered something. It is in the %s." % str(spot.get("room", "property")), "warning")
	Audio.play_sfx("radio_static", Vector3.ZERO, -4.0)
	contract_updated.emit()
	objective_changed.emit()


func _network_tick(delta: float) -> void:
	_sync_timer += delta
	if _sync_timer >= 1.0 / SYNC_HZ:
		_sync_timer = 0.0
		if Net.is_online():
			_sync_furniture()
	# event scheduling
	if state != MState.ACTIVE:
		return
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = _rng.randf_range(50.0, 95.0)
		var pool: Array = property.event_pool if property else []
		if not pool.is_empty():
			trigger_event(str(pool[_rng.randi_range(0, pool.size() - 1)]), {})


func _sync_furniture() -> void:
	if Net.players.size() <= 1:
		return
	for pid in Net.players.keys():
		var id := int(pid)
		if id == 1:
			continue
		var viewer := Game.get_player(id)
		var origin := viewer.global_position if viewer != null else Vector3.ZERO
		var uids := PackedInt32Array()
		var data := PackedFloat32Array()
		var candidates: Array[Furniture] = []
		for f in furniture:
			if not is_instance_valid(f):
				continue
			if origin.distance_squared_to(f.global_position) < SYNC_RADIUS * SYNC_RADIUS:
				candidates.append(f)
		if candidates.size() > MAX_SYNC_OBJECTS:
			candidates.sort_custom(func(a, b): return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
			candidates = candidates.slice(0, MAX_SYNC_OBJECTS)
		for f in candidates:
			uids.append(f.uid)
			f.pack_state(data)
		if uids.size() > 0:
			rpc_id(id, "_rpc_furniture_batch", uids, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_furniture_batch(uids: PackedInt32Array, data: PackedFloat32Array) -> void:
	for i in uids.size():
		var f := furniture_by_uid(int(uids[i]))
		if f != null and is_instance_valid(f):
			f.unpack_state(data, i * 11)


@rpc("authority", "call_remote", "unreliable")
func _rpc_clock(value: float, new_state: int) -> void:
	time_left = value
	state = new_state as MState
	timer_changed.emit(time_left, time_total)


# ------------------------------------------------------------- interactions -

func report_noise(position: Vector3, amount: float) -> void:
	if not Net.is_host():
		return
	var mult := 1.0
	for m in modifiers:
		if m == "noisy":
			mult = 1.6
	noise_position = position
	if creatures != null:
		creatures.on_noise(position, amount)
	_noise_decay = minf(3.0, _noise_decay + amount * mult)
	if _noise_decay > 2.2:
		_noise_decay = 0.0
		_on_loud_noise(position)


func _on_loud_noise(position: Vector3) -> void:
	if property == null:
		return
	property.on_loud_noise(self, position)
	Audio.play_sfx("house_react", position, -6.0)


func highlight_furniture(f: Furniture) -> void:
	if _highlight_target == f:
		return
	if _highlight_target and is_instance_valid(_highlight_target):
		_highlight_target.highlight(false)
	_highlight_target = f
	if f:
		f.highlight(true)


func furniture_by_uid(uid: int) -> Furniture:
	return _furn_by_uid.get(uid, null)


func truck_spawn_point() -> Vector3:
	if truck:
		return truck.player_spawn_point()
	return property.player_spawns[0] if property and not property.player_spawns.is_empty() else Vector3(0, 1, 0)


func player_spawn(index: int) -> Transform3D:
	if property and not property.player_spawns.is_empty():
		return property.player_spawns[index % property.player_spawns.size()]
	return Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0))


# ---------------------------------------------------------------- delivery --

func _on_furniture_loaded(f: Furniture) -> void:
	Audio.play_sfx("truck_load", f.global_position, 0.0)
	if not Net.is_host():
		return
	if f.is_required:
		required_delivered += 1
	elif f.is_optional:
		optional_delivered += 1
	else:
		unauthorised_loaded.append(str(f.data.get("name", "Object")))
		notification.emit("Unauthorised item loaded: %s. Management has noticed." % f.data.get("name", "Object"), "info")
	if Net.is_online():
		rpc("_rpc_delivery", f.uid, f.is_required, f.is_optional)
	if creatures != null and required_total > 0:
		creatures.on_progress(float(required_delivered) / float(required_total))
	_maybe_spawn_extra_item()
	objective_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_delivery(_uid: int, is_req: bool, is_opt: bool) -> void:
	if is_req:
		required_delivered += 1
	elif is_opt:
		optional_delivered += 1
	objective_changed.emit()


func _on_capacity_warning(count: int, capacity: int) -> void:
	notification.emit("Cargo bay over capacity (%d/%d). Unsecured items will not be insured." % [count, capacity], "warning")


func _on_furniture_damaged(amount: float, was_destroyed: bool, f: Furniture = null) -> void:
	if not Net.is_host():
		return
	var mult := effect("damage_penalty", 1.0)
	property_damage += amount * 100.0 * mult
	if was_destroyed:
		notification.emit("Equipment destroyed. It has been added to your invoice.", "damage")
		if has_effect("equip_penalty"):
			equipment_losses += 180.0 * effect("equip_penalty", 1.0)
			notification.emit("Uninsured crew: $%d of equipment charged to the crew." % int(equipment_losses), "warning")
		if f != null and f.is_required:
			required_destroyed += 1
			# the whole contract in splinters: the company has a word for that
			if required_destroyed >= required_total:
				Save.set_achievement("not_insured")


func _on_furniture_picked_up(holder_ids: Array) -> void:
	if holder_ids.size() >= 2 and Net.is_host():
		Save.bump_stat("crew_carries", 1)
		if holder_ids.size() >= 4:
			Save.set_achievement("four_hands")


func _on_furniture_dropped() -> void:
	pass


func _on_furniture_delivered(_value: bool) -> void:
	pass


func on_furniture_destroyed(f: Furniture) -> void:
	if not Net.is_host():
		return
	_furn_by_uid.erase(f.uid)
	notification.emit("%s destroyed." % f.data.get("name", "Object"), "damage")
	if f.is_required:
		objective_changed.emit()


func on_player_downed(_p: Player) -> void:
	crew_downed += 1
	Save.bump_stat("deaths", 1)


func on_player_missing(_p: Player) -> void:
	crew_lost += 1
	notification.emit("Employee missing. The paperwork has already been filed.", "warning")


func on_living_furniture_agitated(f: Furniture) -> void:
	if property:
		property.on_living_furniture(self, f)


# ------------------------------------------------------------------ events --

func trigger_event(event_name: String, data: Dictionary) -> void:
	events_fired.append(event_name)
	if Net.is_online() and Net.is_host():
		rpc("_rpc_event", event_name, data)
	_apply_event(event_name, data)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(event_name: String, data: Dictionary) -> void:
	_apply_event(event_name, data)


func _apply_event(event_name: String, data: Dictionary) -> void:
	event_triggered.emit(event_name, data)
	if property:
		property.handle_event(self, event_name, data)


# ------------------------------------------------------------- completion ---

## Object Detector upgrade: the closest contracted item that is not yet loaded.
func nearest_required(from: Vector3) -> Furniture:
	var best: Furniture = null
	var best_d := 1.0e9
	for f in furniture:
		if not is_instance_valid(f) or not f.is_required or f.delivered or not f.is_alive:
			continue
		var d := f.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = f
	return best


func request_departure() -> void:
	if not Net.is_host() or state == MState.ENDED:
		return
	# The truck leaves with the whole crew or not at all. Anyone still downed counts as
	# cargo, not as crew, so a downed mover never holds the truck hostage.
	var away: Array[String] = []
	if Net.players.size() > 1:
		for pid in Net.players.keys():
			var p := Game.get_player(int(pid))
			if p == null or p.is_downed:
				continue
			if p.global_position.distance_to(truck.depart_point()) > MUSTER_RADIUS:
				away.append(Net.display_name(int(pid)))
	if not away.is_empty():
		notification.emit("The truck leaves with the whole crew. Still inside: %s." % ", ".join(away), "warning")
		Audio.play_sfx("radio_static", truck.depart_point(), -6.0)
		muster_warning.emit(away)
		return
	notification.emit("Departed with %d/%d contracted items." % [required_delivered, required_total], "info")
	_finish(true)


func fail_mission(reason: String) -> void:
	if not Net.is_host() or state == MState.ENDED:
		return
	notification.emit(reason, "warning")
	_finish(false, reason)


func _finish(_holding: bool, reason := "") -> void:
	if _reported_end:
		return
	_reported_end = true
	if creatures != null and Net.is_host():
		creatures.enabled = false
	state = MState.ENDED
	var result := build_result(reason)
	if Net.is_online():
		rpc("_rpc_mission_result", result)
	mission_ended.emit(result)


@rpc("authority", "call_remote", "reliable")
func _rpc_mission_result(result: Dictionary) -> void:
	state = MState.ENDED
	mission_ended.emit(result)


func build_result(reason := "") -> Dictionary:
	var prop_def := DB.get_property(property_id)
	var base_pay := float(prop_def.get("base_pay", 900))
	var value_mult := 1.0
	for m in modifiers:
		var md := DB.get_modifier(m)
		value_mult *= float(md.get("value_mult", 1.0))

	var required_value := 0
	var delivered_value := 0
	var delivered_names: Array = []
	var missing_names: Array = []
	var optional_value := 0
	for f in furniture:
		if not is_instance_valid(f):
			continue
		if f.is_required:
			required_value += f.base_value
			if f.delivered:
				delivered_value += f.current_value()
				delivered_names.append(f.data.get("name", "Object"))
			else:
				missing_names.append(f.data.get("name", "Object"))
		elif f.is_optional and f.delivered:
			optional_value += f.current_value()
	var completion := 0.0
	if required_total > 0:
		completion = float(required_delivered) / float(required_total)

	var damage_penalty := property_damage * 0.55
	var time_bonus := 0.0
	if time_left > 0.0 and time_total > 0.0:
		time_bonus = base_pay * 0.22 * (time_left / time_total)
	# the crew bonus only counts if the crew actually moved something
	var survival_bonus := base_pay * 0.1 * clampf(1.0 - float(crew_lost) * 0.5, 0.0, 1.0) if completion >= 0.34 else 0.0
	survival_bonus += 45.0 * float(creatures_banished)
	if crew_lost > 0:
		survival_bonus = 0.0
	var payout := (base_pay * completion) * value_mult + optional_value * 0.75 + time_bonus + survival_bonus - damage_penalty
	if has_effect("inspection"):
		# a supervisor is watching: sloppy work is judged harshly
		payout -= damage_penalty * 0.6
	payout -= equipment_losses
	if state == MState.OVERDUE or time_left < 0.0:
		payout *= 0.6
	payout = maxf(0.0, payout)
	var success := completion >= 0.999
	var partial := completion >= 0.34

	var report := _build_report(completion, delivered_value, damage_penalty, missing_names)
	return {
		"property_id": property_id,
		"title": prop_def.get("title", "Contract"),
		"code": prop_def.get("code", "PROPERTY"),
		"success": success,
		"partial": partial,
		"reason": reason,
		"required_delivered": required_delivered,
		"required_total": required_total,
		"optional_delivered": optional_delivered,
		"optional_total": optional_total,
		"required_value": required_value,
		"delivered_value": delivered_value,
		"optional_value": optional_value,
		"damage_penalty": int(damage_penalty),
		"property_damage": int(property_damage),
		"time_left": time_left,
		"time_total": time_total,
		"crew_lost": crew_lost,
		"crew_downed": crew_downed,
		"payout": int(round(payout)),
		"modifiers": modifiers.duplicate(),
		"missing": missing_names,
		"delivered": delivered_names,
		"unauthorised": unauthorised_loaded.duplicate(),
		"report": report,
		"events": events_fired.size(),
		"creatures_banished": creatures_banished,
		"seed": seed_value,
	}


func _build_report(completion: float, delivered_value: int, damage_penalty: float, missing: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s%d" % [property_id, required_delivered * 31 + int(property_damage)])
	var group := "open_good" if completion >= 0.9 else ("open_mid" if completion >= 0.4 else "open_bad")
	var open_line := DB.random_line(group, rng)
	open_line = open_line.replace("{recovered}", str(required_delivered)).replace("{required}", str(required_total))
	var body: Array[String] = []
	if property_damage > 40.0:
		body.append(DB.random_line("body_lines_damage", rng).replace("{damage}", U.fmt_money(int(property_damage))))
	if crew_lost > 0:
		body.append(DB.random_line("body_lines_crew", rng).replace("{missing}", "unnamed"))
	if not missing.is_empty():
		body.append("Missing from the manifest: %s." % U.join_words(missing.slice(0, 4)))
	var time_line := DB.random_line("body_lines_time", rng)
	time_line = time_line.replace("{time}", U.fmt_clock(maxf(0.0, time_total - time_left))).replace("{remaining}", U.fmt_clock(maxf(0.0, time_left)))
	body.append(time_line)
	var penalty := 0
	if delivered_value > 0:
		penalty = clampi(int(round((damage_penalty + float(maxi(0, required_total - required_delivered)) * 60.0) / maxf(1.0, float(delivered_value)) * 100.0)), 0, 100)
	var close_line := DB.random_line("close", rng).replace("{penalty}", str(penalty))
	return {
		"open": open_line,
		"body": body,
		"close": close_line,
		"penalty_pct": penalty,
	}
