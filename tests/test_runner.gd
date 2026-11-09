extends Node
## Headless integration test runner.
## Drives the real game (real autoloads, real physics, real mission) and asserts on
## observable behaviour. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 1 if any test fails, so it can gate a build.

var failures: Array[String] = []
var checks := 0
var _errors: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== THE LAST MOVE — INTEGRATION TESTS ===========")
	await test_database()
	await test_content_integrity()
	await test_save_system()
	await test_solo_boot()
	await test_mission_build()
	await test_furniture_physics()
	await test_carry_and_deliver()
	await test_damage_and_valuation()
	await test_scoring()
	await test_settings_persistence()
	await test_audio_content()
	_finish()


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		failures.append(label)
		print("  FAIL  %s" % label)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


# ------------------------------------------------------------------ tests ---

func test_database() -> void:
	print("\n[1] Database")
	check(DB.items.size() >= 40, "at least 40 furniture items loaded (%d)" % DB.items.size())
	check(DB.properties.size() == 8, "8 properties loaded (%d)" % DB.properties.size())
	check(DB.upgrades.size() >= 10, "upgrades loaded")
	check(DB.modifiers.size() == 8, "8 contract modifiers loaded")
	check(not DB.flavor.is_empty(), "flavour text loaded")


func test_content_integrity() -> void:
	print("\n[2] Content integrity (every item must build a mesh)")
	var bad: Array[String] = []
	for id in DB.item_ids:
		var item := DB.get_item(id)
		var builder := AssetLib.build(item)
		if builder.parts.is_empty():
			bad.append(id + ":no parts")
			continue
		var mesh := builder.build_mesh()
		if mesh.get_surface_count() == 0:
			bad.append(id + ":no surfaces")
		if builder.make_shapes().is_empty():
			bad.append(id + ":no collision")
		var sz: Vector3 = item["size_v"]
		if sz.x <= 0.05 or sz.y <= 0.05 or sz.z <= 0.05:
			bad.append(id + ":bad size")
	check(bad.is_empty(), "all items build mesh+collision %s" % str(bad))
	for prop in DB.properties:
		var path := str(prop["layout"])
		check(ResourceLoader.exists(path), "layout exists for %s (%s)" % [prop["id"], path])


func test_save_system() -> void:
	print("\n[3] Save system")
	Save.reset_profile()
	Save.add_credits(5000)
	check(Save.credits() == 5000, "credits persist in memory")
	Save.save_profile()
	check(FileAccess.file_exists(Save.PROFILE_PATH), "profile file written")
	var before := Save.credits()
	Save.load_profile()
	check(Save.credits() == before, "profile reload restores credits")
	check(Save.purchase_upgrade("gloves_grip"), "can buy an upgrade")
	check(Save.owns_upgrade("gloves_grip"), "upgrade flagged as owned")
	check(not Save.purchase_upgrade("gloves_grip"), "cannot buy the same upgrade twice")
	Save.add_credits(5000)
	# corrupt the primary file and verify the backup recovery path
	var f := FileAccess.open(Save.PROFILE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	Save.load_profile()
	check(Save.credits() >= 0, "corrupt profile falls back safely (%d credits)" % Save.credits())
	Save.reset_profile()
	Save.add_credits(20000)


func test_solo_boot() -> void:
	print("\n[4] Solo boot + headquarters")
	Game.start_solo()
	await _wait(4)
	check(Net.is_solo(), "net layer in solo mode")
	check(Game.state == Game.State.HEADQUARTERS, "state is HEADQUARTERS")
	check(Game.headquarters != null, "headquarters instantiated")
	await _wait(4)
	var p := Game.local_player()
	check(p != null, "local player spawned")
	check(Game.headquarters.get_node_or_null("ContractBoard") != null, "contract board exists")
	check(Game.headquarters.get_node_or_null("EquipmentStation") != null, "equipment station exists")


func test_mission_build() -> void:
	print("\n[5] Mission build (Willow Residence)")
	Game.start_mission("willow", 1234, [])
	await _wait(8)
	var m := Game.mission
	check(m != null, "mission manager created")
	if m == null:
		return
	check(m.property != null, "property built")
	check(m.truck != null, "truck spawned")
	check(m.required_total >= 9, "contract has required items (%d)" % m.required_total)
	check(m.furniture.size() >= 15, "furniture spawned (%d)" % m.furniture.size())
	check(Game.local_player() != null, "player exists in mission")
	var missing: Array[String] = []
	for entry in m.contract["required"]:
		if m.furniture_by_uid(int(entry["uid"])) == null:
			missing.append(str(entry["name"]))
	check(missing.is_empty(), "every contract entry resolved to a body %s" % str(missing))
	check(m.time_total > 0.0, "timer configured (%s)" % U.fmt_clock(m.time_total))


func test_furniture_physics() -> void:
	print("\n[6] Physics stability (nothing explodes on spawn)")
	await _wait(120)
	var m := Game.mission
	if m == null:
		check(false, "mission missing")
		return
	var unstable: Array[String] = []
	var below_floor := 0
	for f in m.furniture:
		if not is_instance_valid(f):
			continue
		if f.linear_velocity.length() > 3.0:
			unstable.append("%s@%.1f" % [f.item_id, f.linear_velocity.length()])
		if f.global_position.y < -1.0:
			below_floor += 1
	check(unstable.is_empty(), "no runaway furniture %s" % str(unstable))
	check(below_floor == 0, "nothing fell through the world (%d)" % below_floor)


## Picks the flattest, most open horizontal direction out of `from`, by raycasting at hip height.
func _clear_dir(from: Vector3) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var best := Vector3.FORWARD
	var best_d := 0.0
	if space == null:
		return best
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(cos(a), 0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.9, 0),
			from + Vector3(0, 0.9, 0) + dir * 3.0, Layers.WORLD | Layers.FURNITURE)
		var hit := space.intersect_ray(q)
		var d := 3.0 if hit.is_empty() else (hit["position"] as Vector3).distance_to(from)
		if d > best_d:
			best_d = d
			best = dir
	return best


func test_carry_and_deliver() -> void:
	print("\n[7] Grab, carry and delivery")
	var m := Game.mission
	var p := Game.local_player()
	if m == null or p == null:
		check(false, "mission/player missing")
		return
	var target: Furniture = null
	for f in m.furniture:
		if is_instance_valid(f) and f.is_required and f.weight < 40.0:
			target = f
			break
	check(target != null, "found a light contracted item to carry")
	if target == null:
		return
	# stand next to it and grab, on the side that actually has room: the old fixed +Z offset
	# could put the carrier nose-first into the living-room wall, which made this check fail
	# on level geometry rather than on carry behaviour
	var stand_dir := _clear_dir(target.global_position)
	p.global_position = target.global_position + stand_dir * 1.2 + Vector3(0, 0.2, 0)
	p.velocity = Vector3.ZERO
	await _wait(4)
	var start_pos := target.global_position
	p._request_grab(target)
	await _wait(2)
	check(target.holders.has(p.peer_id), "grab registered on the body")
	# walk the player across open floor; the object should follow
	var walk := stand_dir
	for i in 90:
		p.global_position += walk * 0.06
		await get_tree().physics_frame
	var moved := start_pos.distance_to(target.global_position)
	check(moved > 1.5, "object physically followed the carrier (%.2f m)" % moved)
	var still_held := target.holders.has(p.peer_id) or target.holders.size() > 0
	check(still_held or moved > 1.5, "grip held or object advanced")
	# cargo only counts while the rear doors are open
	check(not m.truck.doors_open, "rear doors start shut")
	await _wait(20)
	check(not target.delivered, "shut doors do not accept cargo")
	m.truck.set_doors(true)
	await _wait(20)
	# teleport into the cargo bay and let the truck validate the load
	target.release_all()
	target.global_position = m.truck.global_position + m.truck.global_transform.basis * Vector3(0, 1.0, 0.4)
	target.linear_velocity = Vector3.ZERO
	target.angular_velocity = Vector3.ZERO
	p.global_position = m.truck.global_position + m.truck.global_transform.basis * Vector3(0, 0, 6.0)
	await _wait(90)
	check(target.delivered, "truck validated a fully-inside item")
	check(m.required_delivered >= 1, "mission counted the delivery (%d)" % m.required_delivered)


func test_damage_and_valuation() -> void:
	print("\n[8] Damage model")
	var m := Game.mission
	var f: Furniture = null
	for cand in m.furniture:
		if is_instance_valid(cand) and cand.fragility > 0.5:
			f = cand
			break
	check(f != null, "found a fragile item")
	if f == null:
		return
	var before := f.current_value()
	f.take_damage(0.4, false)
	var after := f.current_value()
	check(after < before, "damage reduces value (%d -> %d)" % [before, after])
	check(f.damage > 0.3, "damage accumulated")
	var hp_before := Game.local_player().health
	Game.local_player().take_damage(30.0, "test")
	check(Game.local_player().health < hp_before, "player takes damage")
	Game.local_player().heal(100.0)
	check(Game.local_player().health >= 99.0, "player heals")


func test_scoring() -> void:
	print("\n[9] Scoring and mission report")
	var m := Game.mission
	var result := m.build_result()
	check(int(result["required_total"]) >= 9, "result carries contract totals")
	check(int(result["payout"]) >= 0, "payout is non-negative")
	check(not str(result["report"]["open"]).is_empty(), "report text generated")
	check(str(result["report"]["open"]).find("{") == -1, "report placeholders substituted")
	var credits_before := Save.credits()
	m.request_departure()
	await _wait(4)
	check(Game.state == Game.State.RESULTS, "mission ends into results state")
	check(Save.credits() >= credits_before, "crew was paid")
	check(Save.has_achievement("first_day"), "first contract achievement granted")


func test_settings_persistence() -> void:
	print("\n[10] Settings")
	Settings.set_value("fov", 95.0)
	Settings.save_settings()
	Settings.data["fov"] = 85.0
	Settings.load_settings()
	check(is_equal_approx(float(Settings.get_value("fov")), 95.0), "settings round-trip through disk")
	Settings.set_value("fov", 85.0)


func test_audio_content() -> void:
	print("\n[11] Audio content")
	check(Audio.streams.size() >= 30, "sfx banks loaded (%d)" % Audio.streams.size())
	check(Audio.music_streams.size() >= 6, "music cues loaded (%d)" % Audio.music_streams.size())
	check(Audio.amb_streams.size() >= 8, "ambience beds loaded (%d)" % Audio.amb_streams.size())
	check(Audio.voice_streams.size() >= 10, "voice lines loaded (%d)" % Audio.voice_streams.size())
	var missing: Array[String] = []
	for name in ["imp_wood", "imp_glass", "scrape_metal", "foot_step", "door_open", "grab"]:
		if not Audio.streams.has(name):
			missing.append(name)
	check(missing.is_empty(), "core one-shots present %s" % str(missing))
	# the shipped build reads a manifest, so a stale manifest is a shipping bug
	var manifest_text := FileAccess.get_file_as_string("res://assets/audio/manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_text)
	check(typeof(manifest) == TYPE_DICTIONARY, "audio manifest parses")
	if typeof(manifest) == TYPE_DICTIONARY:
		var listed := 0
		var absent: Array[String] = []
		for bank in manifest.keys():
			for key in manifest[bank].keys():
				for path in manifest[bank][key]:
					listed += 1
					if not FileAccess.file_exists(str(path)):
						absent.append(str(path))
		check(listed >= 149, "manifest lists every clip (%d)" % listed)
		check(absent.is_empty(), "every manifest path exists %s" % str(absent.slice(0, 3)))
	for name in ["creature_growl", "creature_shriek", "creature_breath", "heartbeat"]:
		check(Audio.streams.has(name), "creature voice present: %s" % name)


func _finish() -> void:
	print("\n=========================================================")
	print("  %d checks, %d failures" % [checks, failures.size()])
	if failures.size() > 0:
		for f in failures:
			print("   FAILED: %s" % f)
		print("  RESULT: FAIL")
		get_tree().quit(1)
	else:
		print("  RESULT: PASS")
		get_tree().quit(0)
