extends Node
## Full campaign run: all eight properties, contract to payout to progression to ending.
## Every delivery goes through the real truck validation, the real scoring and the real
## save file, with no shortcuts other than teleporting the crate into the cargo hold.

var checks := 0
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== CAMPAIGN TEST ===========")
	Save.reset_profile()
	Game.start_solo()
	await get_tree().process_frame
	var props: Array = DB.properties
	_check(props.size() == 8, "campaign has 8 properties (%d)" % props.size())
	var expected_pay := 0
	for i in props.size():
		var pid := str(props[i]["id"])
		_check(Save.is_property_unlocked(pid), "%s unlocked at campaign step %d" % [pid, i + 1])
		await _run_contract(pid, i)
		expected_pay += 1
		await get_tree().process_frame
	# final state of the save file
	_check(Save.has_achievement("campaign_complete") or Save.has_completed("last_customer"),
		"campaign completion recorded")
	_check(Save.credits() > 0, "crew banked credits (%s)" % U.fmt_money(Save.credits()))
	print("  credits after full run: %s" % U.fmt_money(Save.credits()))
	print("  items delivered stat: %.0f" % float(Save.profile.get("stats", {}).get("items_delivered", 0)))
	_finish()


func _run_contract(pid: String, index: int) -> void:
	Game.start_mission(pid, 1000 + index, [])
	await get_tree().process_frame
	var m := Game.mission
	_check(m != null, "%s: mission built" % pid)
	if m == null:
		return
	_check(m.required_total >= 5, "%s: %d contracted items" % [pid, m.required_total])
	# stand next to the truck so departure is allowed
	var player: Player = Game.get_player(1)
	if player != null and m.truck != null:
		player.global_position = m.truck.depart_point() + Vector3(0, 0.4, 0)
	# open the rear doors: cargo only counts while they are open
	m.truck.set_doors(true)
	await get_tree().physics_frame
	# deliver every required item through the cargo zone. A contract can grow while it is
	# being played (the "one last item" modifier adds one when the crew passes a third
	# delivered), so keep sweeping until nothing new turns up.
	var target: Vector3 = m.truck.interior_point() + Vector3(0, -0.55, 0)
	for sweep in 4:
		var moved := 0
		for f in m.furniture.duplicate():
			if not is_instance_valid(f) or not f.is_required or f.delivered:
				continue
			moved += 1
			f.freeze = true
			f.global_position = target
			f.linear_velocity = Vector3.ZERO
			for k in 20:
				await get_tree().physics_frame
		if moved == 0:
			break
		await get_tree().physics_frame
	var delivered := m.required_delivered
	_check(delivered == m.required_total,
		"%s: %d/%d items validated in cargo" % [pid, delivered, m.required_total])
	m.request_departure()
	for k in 12:
		await get_tree().process_frame
	_check(Game.state == Game.State.RESULTS, "%s: results state reached" % pid)
	var res: Dictionary = Game.last_result
	_check(int(res.get("payout", 0)) > 0, "%s: payout %s" % [pid, U.fmt_money(int(res.get("payout", 0)))])
	_check(bool(res.get("success", false)), "%s: contract marked successful" % pid)
	_check(Save.has_completed(pid), "%s: recorded as completed" % pid)
	if index + 1 < DB.properties.size():
		var next_id := str(DB.properties[index + 1]["id"])
		_check(Save.is_property_unlocked(next_id), "%s: unlocked %s" % [pid, next_id])
	await get_tree().process_frame
	Game.return_to_headquarters()
	for k in 3:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("  %d checks, %d failures" % [checks, failures])
	print("  RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(1 if failures > 0 else 0)
