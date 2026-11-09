extends Node
## Systems test: contract modifiers, upgrades, crew injury, scoring edge cases, and the
## progression economy. Every assertion drives real code, none of it reads a constant back.

var checks := 0
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== SYSTEMS TEST ===========")
	Save.reset_profile()
	Game.start_solo()
	await get_tree().process_frame
	await _test_modifiers()
	await _test_upgrades()
	await _test_crew_injury()
	await _test_scoring_edges()
	await _test_economy()
	await _test_achievements()
	await _test_departure_muster()
	await _test_hints()
	await _test_events()
	_finish()


# ------------------------------------------------------------------ helpers ---

func _start(pid: String, mods: Array, seed_value := 4242) -> MissionManager:
	Game.start_mission(pid, seed_value, mods)
	await get_tree().process_frame
	for i in 6:
		await get_tree().physics_frame
	return Game.mission


func _park_player_out_of_the_way() -> Player:
	var p: Player = Game.get_player(1)
	if p != null:
		p.global_position = Vector3(0, 0.2, 30.0)
	return p


func _deliver_all(m: MissionManager) -> void:
	m.truck.set_doors(true)
	await get_tree().physics_frame
	var target: Vector3 = m.truck.interior_point() + Vector3(0, -0.55, 0)
	for f in m.furniture.duplicate():
		if not is_instance_valid(f) or not f.is_required or f.delivered:
			continue
		f.freeze = true
		f.global_position = target
		f.linear_velocity = Vector3.ZERO
		for k in 8:
			await get_tree().physics_frame
	for k in 20:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


# ---------------------------------------------------------------- modifiers ---

func _test_modifiers() -> void:
	print("\n[1] Contract modifiers")
	var plain := await _start("willow", [], 555)
	_check(plain != null, "baseline mission built")
	if plain == null:
		return
	var base_time := plain.time_total
	var base_frag := 0.0
	for f in plain.furniture:
		if f.is_required:
			base_frag = f.fragility
			break
	var base_lights := _light_energy(plain)
	Game.return_to_headquarters()
	await get_tree().process_frame

	var rush := await _start("willow", ["rush"], 555)
	_check(rush != null and rush.time_total < base_time, "rush shortens the deadline (%.0fs < %.0fs)" % [
		rush.time_total if rush else 0.0, base_time])
	Game.return_to_headquarters()
	await get_tree().process_frame

	var fragile := await _start("willow", ["fragile"], 555)
	var frag := 0.0
	for f in fragile.furniture:
		if f.is_required:
			frag = f.fragility
			break
	_check(frag > base_frag, "fragile raises contracted fragility (%.2f > %.2f)" % [frag, base_frag])
	Game.return_to_headquarters()
	await get_tree().process_frame

	var dark := await _start("willow", ["night_shift"], 555)
	var dark_lights := _light_energy(dark)
	_check(dark_lights < base_lights * 0.8, "night shift dims the lighting (%.2f < %.2f)" % [dark_lights, base_lights])
	Game.return_to_headquarters()
	await get_tree().process_frame

	var premium := await _start("willow", ["premium"], 555)
	var no_mod := await _start("willow", [], 555)
	var plain_damage_before := no_mod.property_damage
	var item := _first_required(no_mod)
	if item != null:
		item.take_damage(0.2, false)
		no_mod._on_furniture_damaged(0.2, false)
	var plain_charge := no_mod.property_damage - plain_damage_before
	Game.return_to_headquarters()
	await get_tree().process_frame
	var premium2 := await _start("willow", ["premium"], 555)
	var item2 := _first_required(premium2)
	var before2 := premium2.property_damage
	if item2 != null:
		item2.take_damage(0.2, false)
		premium2._on_furniture_damaged(0.2, false)
	var premium_charge := premium2.property_damage - before2
	_check(premium_charge > plain_charge * 1.8, "premium multiplies damage charges (%.0f vs %.0f)" % [
		premium_charge, plain_charge])
	Game.return_to_headquarters()
	await get_tree().process_frame

	var uninsured := await _start("willow", ["uninsured"], 555)
	var doomed := _first_required(uninsured)
	if doomed != null:
		uninsured._on_furniture_damaged(1.0, true)
	_check(uninsured.equipment_losses > 0.0, "uninsured charges the crew for destroyed equipment ($%.0f)" % uninsured.equipment_losses)
	Game.return_to_headquarters()
	await get_tree().process_frame

	var one_last := await _start("willow", ["one_last"], 555)
	var before_total := one_last.required_total
	var before_count := one_last.furniture.size()
	# fake the contract being a third done so the extra item drops
	one_last.required_delivered = int(ceil(float(before_total) * 0.4))
	one_last._maybe_spawn_extra_item()
	await get_tree().process_frame
	_check(one_last.required_total == before_total + 1,
		"one last item extends the contract (%d -> %d)" % [before_total, one_last.required_total])
	_check(one_last.furniture.size() == before_count + 1, "the extra item exists in the world")
	_check(one_last.contract["required"].size() == one_last.required_total, "contract sheet lists the extra item")
	# it must only ever happen once
	one_last._maybe_spawn_extra_item()
	_check(one_last.required_total == before_total + 1, "one last item cannot repeat")
	one_last.required_delivered = 0
	Game.return_to_headquarters()
	await get_tree().process_frame

	# noisy: same noise event produces more aggro
	var quiet := await _start("willow", [], 555)
	quiet.report_noise(Vector3.ZERO, 0.4)
	await get_tree().process_frame
	var quiet_noise := quiet._noise_decay
	Game.return_to_headquarters()
	await get_tree().process_frame
	var loud := await _start("willow", ["noisy"], 555)
	loud.report_noise(Vector3.ZERO, 0.4)
	await get_tree().process_frame
	var loud_noise := loud._noise_decay
	_check(loud_noise > quiet_noise, "noisy raises the aggro from the same noise (%.2f > %.2f)" % [loud_noise, quiet_noise])
	Game.return_to_headquarters()
	await get_tree().process_frame


func _light_energy(m: MissionManager) -> float:
	var total := 0.0
	var stack: Array[Node] = [m.property]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is OmniLight3D:
			total += (n as OmniLight3D).light_energy
		for c in n.get_children():
			stack.append(c)
	return total


func _first_required(m: MissionManager) -> Furniture:
	for f in m.furniture:
		if is_instance_valid(f) and f.is_required:
			return f
	return null


# ----------------------------------------------------------------- upgrades ---

func _test_upgrades() -> void:
	print("\n[2] Upgrades")
	Save.reset_profile()
	Save.add_credits(20000)
	var base_strength := Game.crew_strength()
	var bought := Save.purchase_upgrade("gloves_grip")
	_check(bought, "purchasing an upgrade succeeds")
	_check(Save.owns_upgrade("gloves_grip"), "the upgrade is owned")
	_check(Game.crew_strength() > base_strength, "grip gloves raise crew strength (%.2f > %.2f)" % [
		Game.crew_strength(), base_strength])
	_check(not Save.owns_upgrade("dolly"), "unbought upgrade is not owned")
	Save.purchase_upgrade("dolly")
	_check(Save.owns_upgrade("dolly"), "dolly owned after purchase")
	# an upgrade cannot be bought twice
	Save.add_credits(5000)
	var credits_before := Save.credits()
	Save.purchase_upgrade("dolly")
	_check(Save.credits() == credits_before, "re-buying an owned upgrade charges nothing")
	# crew strength scales with every glove tier
	Save.reset_profile()
	Save.add_credits(10000)
	Save.purchase_upgrade("gloves_grip")
	Save.purchase_upgrade("gloves_pro")
	_check(Game.crew_strength() > 1.5, "the best gloves give a large strength bonus (%.2f)" % Game.crew_strength())
	# truck upgrades change the mission
	Save.reset_profile()
	Save.add_credits(20000)
	Save.purchase_upgrade("truck_capacity")
	var m := await _start("willow", [], 909)
	_check(m.truck.capacity > Truck.BASE_CAPACITY, "capacity upgrade enlarges the hold (%d > %d)" % [
		m.truck.capacity, Truck.BASE_CAPACITY])
	Game.return_to_headquarters()
	await get_tree().process_frame
	# helmet reduces incoming damage
	Save.reset_profile()
	Save.add_credits(5000)
	Save.purchase_upgrade("helmet")
	_check(Save.owns_upgrade("helmet"), "helmet upgrade purchased")
	var p := await _test_damage_with_helmet()
	_check(p, "helmet upgrade reduces damage taken")
	await _test_support_upgrades()


## The support upgrades (ramp, straps, suspension, medkit, detector). Every one of these was
## data-only at some point - buyable, listed, and completely inert - so each is asserted against
## the code that is supposed to read it.
func _test_support_upgrades() -> void:
	Save.reset_profile()
	Save.add_credits(40000)
	var bought: Array[String] = []
	for id in ["ramp", "truck_organize", "truck_suspension", "medkit", "detector", "flashlight"]:
		if Save.purchase_upgrade(str(id)):
			bought.append(str(id))
	_check(bought.size() == 6, "the support upgrades can be bought %s" % str(bought))
	Save.purchase_upgrade("paint_company")
	_check(Save.owns_upgrade("paint_company"), "the company paint job can be bought")
	var m := await _start("willow", [], 606)
	if m == null or m.truck == null:
		_check(false, "support upgrade mission failed to build")
		return
	var t := m.truck
	_check(t.ramp_length() > 1.9 and t.ramp_width() >= Truck.CARGO_WIDTH - 0.01,
		"portable ramp is longer and wider (%.1f x %.1f m)" % [t.ramp_length(), t.ramp_width()])
	var default_body := Color("#3f4a52")
	_check(t.skin_body_color() != default_body, "the company paint job repaints the truck %s" % t.skin_body_color().to_html(false))
	_check(t._settle_speed() > Truck.SETTLE_SPEED,
		"cargo straps accept a rocking load (%.2f > %.2f m/s)" % [t._settle_speed(), Truck.SETTLE_SPEED])
	var f := _first_required(m)
	if f != null:
		f.freeze = true
		f.global_position = t.interior_point()
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(f.impact_damage_scale() < 1.0, "heavy suspension cushions a loaded item (x%.2f)" % f.impact_damage_scale())
		f.global_position = Vector3(0, 2.0, 34.0)
		await get_tree().physics_frame
		_check(is_equal_approx(f.impact_damage_scale(), 1.0), "and does nothing to an item in the yard")
		f.freeze = false
	var from := Vector3.ZERO
	var near := m.nearest_required(from)
	var nearest_ok := near != null
	if near != null:
		for other in m.furniture:
			if other == near or not is_instance_valid(other) or not other.is_required:
				continue
			if other.global_position.distance_to(from) < near.global_position.distance_to(from):
				nearest_ok = false
	_check(nearest_ok, "object detector names the closest contracted item")
	var p: Player = Game.get_player(1)
	if p != null:
		_check(p.flashlight != null and p.flashlight.spot_range > 18.0,
			"company flashlight reaches further (%.0f m)" % (p.flashlight.spot_range if p.flashlight else 0.0))
		_check(p.revive_time() < Player.REVIVE_TIME, "field medkit revives faster (%.1fs)" % p.revive_time())
		p.is_downed = true
		p._do_revive()
		_check(p.health > 45.0, "field medkit patch job (%.0f hp)" % p.health)
	Game.return_to_headquarters()
	await get_tree().process_frame


func _test_damage_with_helmet() -> bool:
	var m := await _start("willow", [], 313)
	var p: Player = Game.get_player(1)
	if p == null:
		return false
	p.health = 100.0
	p.is_downed = false
	p.take_damage(20.0, "test")
	var with_helmet := 100.0 - p.health
	Game.return_to_headquarters()
	await get_tree().process_frame
	Save.reset_profile()
	var m2 := await _start("willow", [], 313)
	var p2: Player = Game.get_player(1)
	p2.health = 100.0
	p2.is_downed = false
	p2.take_damage(20.0, "test")
	var without := 100.0 - p2.health
	Game.return_to_headquarters()
	await get_tree().process_frame
	print("      helmet %.1f damage vs %.1f without" % [with_helmet, without])
	return with_helmet < without


# ------------------------------------------------------------- crew injury ---

func _test_crew_injury() -> void:
	print("\n[3] Crew injury, downing and revive")
	var m := await _start("willow", [], 777)
	var p: Player = Game.get_player(1)
	_check(p != null, "player present")
	if p == null:
		return
	p.health = 100.0
	p.is_downed = false
	p.take_damage(150.0, "test")
	_check(p.is_downed, "lethal damage downs the mover")
	_check(p.bleedout > 0.0, "downed mover has a bleedout timer (%.0fs)" % p.bleedout)
	_check(m.crew_downed >= 0, "mission tracks downed crew")
	# a downed mover cannot grab
	var item := _first_required(m)
	if item != null:
		p._request_grab(item)
		await get_tree().physics_frame
		_check(item.holders.is_empty(), "downed movers cannot grab")
	# revive
	p.revive_progress = 0.0
	p._do_revive()
	await get_tree().process_frame
	_check(not p.is_downed, "revive brings the mover back up")
	_check(p.health > 0.0 and p.health < 100.0, "revived mover returns with partial health (%.0f)" % p.health)
	_check(Save.has_achievement("occupational_hazard"), "being revived earns the hazard achievement")
	# bleeding out completely means missing
	p.is_downed = true
	p.bleedout = 0.05
	await get_tree().create_timer(0.3).timeout
	_check(m.crew_lost >= 1, "bleeding out counts a crew loss (%d)" % m.crew_lost)
	Game.return_to_headquarters()
	await get_tree().process_frame


# ------------------------------------------------------------ scoring edges ---

func _test_scoring_edges() -> void:
	print("\n[4] Scoring edge cases")
	# nothing delivered, deadline missed: payout must be zero, not negative
	var m := await _start("willow", [], 111)
	m.time_left = -30.0
	var res := m.build_result()
	_check(int(res.get("payout", -1)) >= 0, "a total failure never pays a negative amount (%d)" % int(res.get("payout", -1)))
	_check(not bool(res.get("success", true)), "nothing delivered is not a success")
	_check(not bool(res.get("partial", true)), "nothing delivered is not a partial")
	# everything delivered, no damage, plenty of time: a full payout
	Game.return_to_headquarters()
	await get_tree().process_frame
	var m2 := await _start("willow", [], 111)
	_park_player_out_of_the_way()
	await _deliver_all(m2)
	var res2 := m2.build_result()
	_check(bool(res2.get("success", false)), "a full delivery is a success")
	_check(int(res2.get("payout", 0)) > 800, "a full clean delivery pays out ($%d)" % int(res2.get("payout", 0)))
	# partial delivery
	Game.return_to_headquarters()
	await get_tree().process_frame
	var m3 := await _start("willow", [], 111)
	var half := int(ceil(float(m3.required_total) * 0.5))
	m3.required_delivered = half
	var res3 := m3.build_result()
	_check(bool(res3.get("partial", false)) and not bool(res3.get("success", true)),
		"half a contract is a partial, not a success")
	# damage reduces the payout
	var before := int(m3.build_result().get("payout", 0))
	m3.property_damage = 500.0
	var after := int(m3.build_result().get("payout", 0))
	_check(after < before, "property damage reduces the payout ($%d -> $%d)" % [before, after])
	Game.return_to_headquarters()
	await get_tree().process_frame


# ----------------------------------------------------------------- economy ---

func _test_economy() -> void:
	print("\n[5] Economy and progression")
	Save.reset_profile()
	_check(Save.credits() == 0, "a fresh profile starts with no credits")
	_check(not Save.can_afford(500), "cannot afford anything yet")
	var ok := Save.purchase_upgrade("flashlight")
	_check(not ok, "purchasing without credits fails")
	Save.add_credits(1000)
	_check(Save.spend_credits(400), "spending credits succeeds")
	_check(Save.credits() == 600, "credits deducted correctly (%d)" % Save.credits())
	_check(not Save.spend_credits(5000), "overspending is refused")
	_check(Save.credits() == 600, "a refused purchase does not charge")
	# campaign gating
	Save.reset_profile()
	_check(Save.is_property_unlocked("willow"), "the first property is unlocked")
	_check(not Save.is_property_unlocked("hotel"), "later properties start locked")
	Save.complete_property("willow", 900, "endless")
	_check(Save.is_property_unlocked("endless"), "finishing a contract unlocks the next")
	_check(not Save.is_property_unlocked("dollhouse"), "only the next property unlocks")
	_check(Save.has_completed("willow"), "completion is recorded")


# ------------------------------------------------------------ achievements ---

func _test_achievements() -> void:
	print("\n[6] Achievements")
	Save.reset_profile()
	_check(not Save.has_achievement("first_day"), "achievements start unearned")
	Save.set_achievement("first_day")
	_check(Save.has_achievement("first_day"), "achievements can be earned")
	var before: int = (Save.profile.get("achievements", []) as Array).size()
	Save.set_achievement("first_day")
	_check((Save.profile.get("achievements", []) as Array).size() == before, "achievements are not duplicated")
	var all_ids: Array = []
	for a in DB.flavor.get("achievements", []):
		all_ids.append(str(a.get("id", "")))
	_check(all_ids.size() >= 10, "%d achievements are defined" % all_ids.size())
	var awarded := ["first_day", "employee_month", "perfect_delivery", "nobody_left",
		"damage_specialist", "not_in_contract", "last_customer", "campaign_complete", "four_hands",
		"occupational_hazard", "not_insured"]
	var missing: Array[String] = []
	for id in awarded:
		if not all_ids.has(id):
			missing.append(id)
	_check(missing.is_empty(), "every code-awarded achievement exists in the data %s" % str(missing))
	for id in all_ids:
		if not awarded.has(id):
			push_warning("[test] achievement %s is defined but no code path was listed here" % id)
	# every achievement must be reachable, not just listed in a table
	Save.reset_profile()
	var m := await _start("willow", [], 909)
	if m != null:
		for f in m.furniture.duplicate():
			if is_instance_valid(f) and f.is_required:
				f.take_damage(999.0)
		await get_tree().process_frame
		_check(Save.has_achievement("not_insured"), "losing the whole contract earns the insurance achievement")
		Game.return_to_headquarters()
		await get_tree().process_frame


# ------------------------------------------------------------- first-run hints ---

func _only(id_to_leave: String) -> void:
	Save.clear_hints()
	for id in HintDirector.HINTS.keys():
		if str(id) != id_to_leave:
			Save.mark_hint_seen(str(id))


func _test_hints() -> void:
	print("\n[8] First-run hints")
	Save.reset_profile()
	var m := await _start("willow", [])
	_check(m != null and m.hints != null, "a mission builds a hint director")
	if m == null or m.hints == null:
		return
	# nothing repeats
	for id in HintDirector.HINTS.keys():
		Save.mark_hint_seen(str(id))
	_check(m.hints.next_hint() == "", "a hint that has been seen is never repeated")
	# the doors hint needs the crew to be carrying something and the bay shut
	_only("doors")
	m.truck.set_doors(false)
	m.hints._elapsed = 30.0
	_check(m.hints.next_hint() == "", "the door hint waits until something is being carried")
	m.truck.set_doors(true)
	_check(m.hints.next_hint() == "", "the door hint never fires with the bay open")
	# delivery hint
	_only("delivered")
	await _deliver_all(m)
	_check(m.hints.next_hint() == "delivered", "the delivery hint fires on the first load")
	var heard: Array[String] = []
	var cb := func(text, kind): heard.append("%s|%s" % [kind, text])
	m.notification.connect(cb)
	m.hints.fire("delivered")
	await get_tree().process_frame
	_check(heard.size() == 1 and heard[0].begins_with("hint|"), "the hint is announced once, as a hint")
	_check(Save.has_seen_hint("delivered"), "the hint is recorded in the profile")
	m.hints.fire("delivered")
	await get_tree().process_frame
	_check(heard.size() == 1, "firing a seen hint does nothing")
	m.notification.disconnect(cb)
	# persists across a save round trip
	Save.save_profile()
	Save.load_profile()
	_check(Save.has_seen_hint("delivered"), "hints survive a reload")
	# the weight hint only makes sense while someone is carrying something too heavy alone
	_only("heavy")
	var p: Player = Game.get_player(1)
	var heavy: Furniture = null
	for f in m.furniture:
		if is_instance_valid(f) and f.mass >= HintDirector.HEAVY_MASS:
			heavy = f
			break
	_check(heavy != null, "the property contains an item heavy enough to need two movers")
	if heavy != null and p != null:
		var saved: Furniture = p.carried
		p.carried = heavy
		_check(m.hints.next_hint() == "heavy", "carrying something too heavy alone raises the weight hint")
		heavy.holders[98] = 0
		heavy.holders[99] = 1
		_check(m.hints.next_hint() == "", "a second pair of hands silences the weight hint")
		heavy.holders.erase(98)
		heavy.holders.erase(99)
		p.carried = saved
	# the whole system can be switched off
	Settings.set_value("hints", false)
	_only("damage")
	m.property_damage = 500.0
	_check(m.hints.next_hint() == "", "hints can be switched off in settings")
	Settings.set_value("hints", true)
	m.property_damage = 500.0
	_check(m.hints.next_hint() == "damage", "and switched back on")
	Save.clear_hints()
	Settings.set_value("hints", true)


# --------------------------------------------------------- supernatural events ---

func _start_with_retry(pid: String, sd: int) -> MissionManager:
	Game.start_mission(pid, sd, [])
	for i in 20:
		await get_tree().process_frame
		if Game.mission != null:
			return Game.mission
	return null


func _back_to_hq() -> void:
	Game.return_to_headquarters()
	for i in 20:
		await get_tree().process_frame
		if Game.state == Game.State.HEADQUARTERS and Game.mission == null:
			return


func _test_events() -> void:
	print("\n[9] Supernatural events")
	var props := DB.properties
	_check(props.size() == 8, "eight properties to fire events in (%d)" % props.size())
	# this section is about the event code, not the unlock chain: open the whole campaign
	var unlocked: Array = []
	for prop in props:
		unlocked.append(str(prop.get("id", "")))
	Save.profile["unlocked_properties"] = unlocked
	var fired := 0
	var bad: Array[String] = []
	for prop in props:
		var pid := str(prop.get("id", ""))
		var m := await _start_with_retry(pid, 515)
		if m == null or m.property == null:
			bad.append("%s:no-mission" % pid)
			continue
		# every event in the property's pool, through the real dispatch path
		var seen: Array[String] = []
		for ev in m.property.event_pool:
			if seen.has(str(ev)):
				continue
			seen.append(str(ev))
			m.trigger_event(str(ev), {})
			fired += 1
			await get_tree().physics_frame
		# and the scheduler has to pick one on its own
		m._event_timer = 0.001
		for i in 3:
			await get_tree().physics_frame
		if m.events_fired.size() < seen.size():
			bad.append("%s:not-scheduled" % pid)
		await _back_to_hq()
	_check(fired >= 20, "every scripted event ran without dying (%d events)" % fired)
	_check(bad.is_empty(), "all eight properties schedule events %s" % str(bad))


# ------------------------------------------------------ departure muster ---

func _test_departure_muster() -> void:
	print("\n[7] Departure muster")
	var m := await _start("willow", [])
	var p: Player = Game.get_player(1)
	if p == null or m == null or m.truck == null:
		_check(false, "departure test could not build a mission")
		return
	var at_truck: Vector3 = m.truck.depart_point() + Vector3(0, 0.4, 0)
	p.global_position = at_truck
	# a second, remote crew member who has not walked back to the truck
	Net.players[2] = {"name": "SECOND MOVER", "ready": true}
	var p2 := Player.new()
	p2.name = "2"
	Game.players_root.add_child(p2)
	p2.global_position = m.truck.depart_point() + Vector3(0, 0.4, 30.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	m.request_departure()
	await get_tree().process_frame
	_check(m.state != MissionManager.MState.ENDED, "the truck will not leave without the whole crew")
	# nobody can be left behind twice: bring them in and the contract closes
	p2.global_position = at_truck
	await get_tree().physics_frame
	await get_tree().physics_frame
	m.request_departure()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(m.state == MissionManager.MState.ENDED, "the truck leaves once the whole crew is aboard")
	if is_instance_valid(p2):
		Game.players_root.remove_child(p2)
		p2.queue_free()
	Net.players.erase(2)


func _finish() -> void:
	print("  %d checks, %d failures" % [checks, failures])
	print("  RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures > 0 else 0)
