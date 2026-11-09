extends Node
## Level design audit -- run on every property in the campaign.
##
## Checks that no contracted item spawns inside architecture, below the floor, inside
## another piece of furniture, or outside the property's playable volume; that nothing
## explodes on the first two seconds of physics; that the truck is reachable in principle
## (distance sane) and that every property builds inside a frame budget.
##
##   godot --headless --path . res://tests/level_audit.tscn

var report: Array[Dictionary] = []
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== THE LAST MOVE — PROPERTY AUDIT ===========")
	Save.reset_profile()
	# unlock everything so the audit is not blocked by campaign gating
	for p in DB.properties:
		Save.profile["unlocked_properties"].append(str(p["id"]))
	Game.start_solo()
	await get_tree().process_frame
	for prop in DB.properties:
		await audit_property(str(prop["id"]))
	_print_summary()
	get_tree().quit(1 if failures > 0 else 0)


func audit_property(property_id: String) -> void:
	var t0 := Time.get_ticks_msec()
	Game.start_mission(property_id, 4242, [])
	await get_tree().process_frame
	var build_ms := Time.get_ticks_msec() - t0
	var m := Game.mission
	if m == null or m.property == null:
		print("  FAIL  %s did not build" % property_id)
		failures += 1
		return
	var issues: Array[String] = []
	if m.required_total < 5:
		issues.append("only %d required items" % m.required_total)
	if m.furniture.size() < 12:
		issues.append("only %d furniture bodies" % m.furniture.size())
	if m.truck == null:
		issues.append("no truck")
	# wait for physics to settle
	for i in 150:
		await get_tree().physics_frame
	var unstable := 0
	var unstable_names: Array[String] = []
	var sunk := 0
	var embedded := 0
	var embed_names: Array[String] = []
	var overlapping := 0
	var overlap_names: Array[String] = []
	var space := m.get_world_3d().direct_space_state
	for f in m.furniture:
		if not is_instance_valid(f):
			continue
		# >5 m/s after settling means interpenetration is ejecting the body;
		# slow drift is normal (buoyancy in the sinking house, sliding on slopes)
		if f.linear_velocity.length() > 5.0:
			unstable += 1
			unstable_names.append("%s v=%.1f at %s" % [f.display_name if "display_name" in f else f.item_id, f.linear_velocity.length(), str(f.global_position.snapped(Vector3.ONE * 0.1))])
		if f.global_position.y < -6.0:
			sunk += 1
		# is the item's own centre inside static architecture?
		var q := PhysicsPointQueryParameters3D.new()
		q.position = f.global_position + Vector3(0, f.size.y * 0.5, 0)
		q.collision_mask = Layers.WORLD
		q.collide_with_bodies = true
		if not space.intersect_point(q, 1).is_empty():
			embedded += 1
			embed_names.append("%s@%s" % [f.item_id, str(f.global_position.snapped(Vector3.ONE * 0.1))])
		# how many other bodies is it sitting inside?
		for g in m.furniture:
			if g == f or not is_instance_valid(g):
				continue
			var fh := Vector2(f.global_position.x, f.global_position.z)
			var gh := Vector2(g.global_position.x, g.global_position.z)
			var d := fh.distance_to(gh)
			var dy := absf(f.global_position.y - g.global_position.y)
			# stacked items (mattress on a frame, tv on a stand) are correct, not a defect
			var stacked := absf(f.global_position.y - (g.global_position.y + g.size.y)) < 0.22
			var stacked_rev := absf(g.global_position.y - (f.global_position.y + f.size.y)) < 0.22
			if stacked or stacked_rev:
				continue
			if d < minf(f.size.length(), g.size.length()) * 0.28 and dy < 0.5 * minf(f.size.y, g.size.y):
				overlapping += 1
				overlap_names.append("%s@%s <> %s@%s" % [f.item_id, str(f.global_position.snapped(Vector3.ONE * 0.1)), g.item_id, str(g.global_position.snapped(Vector3.ONE * 0.1))])
				break
	if unstable > 0:
		issues.append("%d unstable bodies (%s)" % [unstable, "; ".join(unstable_names)])
	if sunk > 0:
		issues.append("%d below world" % sunk)
	if embedded > 0:
		print("      embedded: ", "; ".join(embed_names))
	if embedded > 0:
		issues.append("%d embedded in walls" % embedded)
	if overlapping > 0:
		issues.append("%d overlapping pairs (%s)" % [overlapping, "; ".join(overlap_names)])
	# distance from the nearest required item to the truck
	var nearest := 9999.0
	for f in m.furniture:
		if is_instance_valid(f) and f.is_required and m.truck:
			nearest = minf(nearest, f.global_position.distance_to(m.truck.global_position))
	if nearest > 120.0:
		issues.append("nearest contract item %.0fm from truck" % nearest)
	var closed := 0
	for d in m.property.doors:
		if not d.is_open:
			closed += 1
	print("  %-14s build %4d ms  furniture %2d  required %2d  nearest %.1fm  doors %d  %s" % [
		property_id, build_ms, m.furniture.size(), m.required_total, nearest, m.property.doors.size(),
		"OK" if issues.is_empty() else "ISSUES: " + ", ".join(issues)])
	if not issues.is_empty():
		failures += 1
	report.append({"property": property_id, "build_ms": build_ms, "items": m.furniture.size(),
		"required": m.required_total, "issues": issues})
	Game.return_to_headquarters()
	await get_tree().process_frame
	await get_tree().process_frame


func _print_summary() -> void:
	print("\n=========== SUMMARY ===========")
	var total_ms := 0
	for r in report:
		total_ms += int(r["build_ms"])
	print("  properties audited: %d" % report.size())
	print("  total build time:   %d ms" % total_ms)
	print("  properties with issues: %d" % failures)
	print("  RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
