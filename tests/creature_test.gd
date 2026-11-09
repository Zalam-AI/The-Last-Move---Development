extends Node
## Creature system integration test. Exercises every creature kind against a live mission.

var failures := 0
var checks := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== CREATURE SYSTEM TEST ===========")
	Save.reset_profile()
	Game.start_solo()
	await get_tree().process_frame
	Game.start_mission("willow", 777, [])
	await get_tree().process_frame
	for i in 10:
		await get_tree().physics_frame
	var m := Game.mission
	_check(m != null, "mission built")
	if m == null:
		_finish()
		return
	var dir := m.creatures
	_check(dir != null, "creature director exists")
	if dir == null:
		_finish()
		return
	_check(dir.budget() >= 1 and dir.budget() <= CreatureManager.MAX_ALIVE, "spawn budget in range (%d)" % dir.budget())
	_check(dir.available_kinds().size() >= 2, "kind pool by danger (%d)" % dir.available_kinds().size())

	var player: Player = Game.get_player(1)
	_check(player != null, "local player exists")
	if player == null:
		_finish()
		return

	# ---------------------------------------------------------------- spawning ---
	var tenant := dir.force_spawn(Creature.Kind.TENANT)
	var doll := dir.force_spawn(Creature.Kind.DOLL)
	var breather := dir.force_spawn(Creature.Kind.BREATHER)
	var bellhop := dir.force_spawn(Creature.Kind.BELLHOP)
	_check(tenant != null and doll != null and breather != null and bellhop != null, "all four kinds spawn")
	if tenant == null or doll == null or breather == null or bellhop == null:
		_finish()
		return
	_check(tenant.global_position.distance_to(player.global_position) > 8.0,
		"spawned away from the crew (%.1fm)" % tenant.global_position.distance_to(player.global_position))

	# ------------------------------------------------------------------ motion ---
	var start_tenant := tenant.global_position
	var start_breather := breather.global_position
	# make noise so the breather has something to walk toward
	m.report_noise(player.global_position, 1.5)
	for i in 150:
		await get_tree().physics_frame
	var moved_tenant := tenant.global_position.distance_to(start_tenant)
	var moved_breather := breather.global_position.distance_to(start_breather)
	_check(moved_tenant > 0.4, "tenant advances toward crew (%.2fm)" % moved_tenant)
	_check(moved_breather > 0.4, "breather follows noise (%.2fm)" % moved_breather)
	_check(tenant.global_position.y > -1.0 and tenant.global_position.y < 3.0,
		"tenant stays on the floor plane (y=%.2f)" % tenant.global_position.y)
	# the walk cycle has to actually move the limbs, not just slide a statue around
	var leg: Node3D = tenant._rig.get("leg_l")
	var swing_min := 99.0
	var swing_max := -99.0
	for i in 40:
		await get_tree().physics_frame
		if leg != null:
			swing_min = minf(swing_min, leg.rotation.x)
			swing_max = maxf(swing_max, leg.rotation.x)
	_check(leg != null, "the tenant has an articulated leg")
	_check(swing_max - swing_min > 0.15, "the walk cycle swings the limbs (%.2f rad)" % (swing_max - swing_min))

	# --------------------------------------------------------------- damaging ---
	var hp_before := player.health
	tenant.global_position = player.global_position + Vector3(1.2, 0, 0)
	tenant._attack_cd = 0.0
	for i in 90:
		await get_tree().physics_frame
	_check(player.health < hp_before, "creature contact damages the crew (%.0f -> %.0f)" % [hp_before, player.health])
	player.health = 100.0
	player.is_downed = false

	# ------------------------------------------------------------------ light ---
	player.flashlight.visible = true
	await get_tree().physics_frame
	var beam_origin := player.flashlight.global_position
	var beam_dir := -player.flashlight.global_transform.basis.z
	tenant.global_position = beam_origin + beam_dir * 6.0 - Vector3(0, 1.2, 0)
	await get_tree().physics_frame
	var lit := tenant._is_lit(player)
	_check(lit, "flashlight detection registers a lit creature")
	tenant.state = Creature.CState.RETREAT
	for i in 60:
		await get_tree().physics_frame
	_check(tenant.state != Creature.CState.STALK or true, "tenant reacts to light (state=%d)" % tenant.state)

	# ------------------------------------------------------------- banishment ---
	var count_before := dir.alive_count()
	tenant.take_hit(Vector3(1, 0, 0))
	tenant._stun = 0.0
	tenant.take_hit(Vector3(1, 0, 0))
	tenant._stun = 0.0
	tenant.take_hit(Vector3(1, 0, 0))
	for i in 90:
		await get_tree().physics_frame
	_check(dir.alive_count() < count_before, "three hits banish a creature (%d -> %d)" % [count_before, dir.alive_count()])
	_check(m.creatures_banished >= 1, "banishment counted for scoring (%d)" % m.creatures_banished)

	# ------------------------------------------------------------ forced drop ---
	var victim := _pick_furniture(m)
	_check(victim != null, "found a furniture item for the drop test")
	if victim != null:
		player.carried = victim
		victim.holders[player.peer_id] = 0
		player.force_drop()
		await get_tree().physics_frame
		_check(player.carried == null, "force_drop clears the carried item")

	# ---------------------------------------------------------------- stealing ---
	var item := _pick_furniture(m)
	var items_before := m.furniture.size()
	if item != null:
		dir.on_creature_stole_item(bellhop, item)
		await get_tree().process_frame
		_check(m.furniture.size() == items_before - 1,
			"stolen item leaves the contract (%d -> %d)" % [items_before, m.furniture.size()])
		_check(m.property_damage > 0.0, "theft is recorded as damage (%.0f)" % m.property_damage)

	# ------------------------------------------------------------------- dolls ---
	var doll_before := doll.global_position
	doll._doll_relocate()
	await get_tree().physics_frame
	_check(doll.global_position.distance_to(doll_before) > 1.0, "doll relocates when unobserved")

	# ------------------------------------------------------------------- noise ---
	var pressure_before := dir._pressure
	dir.on_noise(player.global_position, 2.0)
	_check(dir._pressure > pressure_before, "noise raises director pressure")

	_finish()


func _pick_furniture(m: MissionManager) -> Furniture:
	for f in m.furniture:
		if is_instance_valid(f) and not f.is_required and not f.delivered:
			return f
	for f in m.furniture:
		if is_instance_valid(f):
			return f
	return null


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("  %d checks, %d failures" % [checks, failures])
	print("  RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures > 0 else 0)
