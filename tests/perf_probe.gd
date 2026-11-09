extends Node
## Measures what can be measured without a GPU: build time, physics cost, process cost,
## node/instance counts and static memory for every property. GPU frame time is *not*
## measured here and is reported as unmeasured in documentation/PERFORMANCE.md.

var rows: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().process_frame
	print("\n=========== PERFORMANCE PROBE (CPU / HEADLESS) ===========")
	Save.reset_profile()
	for p in DB.properties:
		Save.profile["unlocked_properties"].append(str(p["id"]))
	Game.start_solo()
	await get_tree().process_frame
	for prop in DB.properties:
		await _measure(str(prop["id"]))
	print("\n  %-14s %8s %9s %9s %9s %7s %7s %6s %6s" % [
		"property", "build_ms", "phys_med", "phys_p95", "proc_med", "rigid", "meshes", "nodes", "MB"])
	for r in rows:
		print("  %-14s %8d %9.2f %9.2f %9.2f %7d %7d %6d %6.1f" % [
			r["id"], r["build_ms"], r["phys_ms"], r["phys_p95"], r["proc_ms"],
			r["rigid"], r["meshes"], r["nodes"], r["mem_mb"]])
	get_tree().quit(0)


func _measure(pid: String) -> void:
	var t0 := Time.get_ticks_msec()
	Game.start_mission(pid, 31337, [])
	await get_tree().process_frame
	var build_ms := Time.get_ticks_msec() - t0
	# let physics settle, then sample 120 frames
	for i in 90:
		await get_tree().physics_frame
	var phys_samples: Array[float] = []
	var proc_samples: Array[float] = []
	var samples := 240
	for i in samples:
		await get_tree().physics_frame
		phys_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		proc_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	phys_samples.sort()
	proc_samples.sort()
	var rigid := 0
	var meshes := 0
	var nodes := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		nodes += 1
		if n is RigidBody3D:
			rigid += 1
		elif n is MeshInstance3D:
			meshes += 1
		for c in n.get_children():
			stack.append(c)
	rows.append({
		"id": pid,
		"build_ms": build_ms,
		"phys_ms": phys_samples[phys_samples.size() / 2],
		"phys_p95": phys_samples[int(phys_samples.size() * 0.95)],
		"proc_ms": proc_samples[proc_samples.size() / 2],
		"rigid": rigid,
		"meshes": meshes,
		"nodes": nodes,
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
	})
	Game.return_to_headquarters()
	await get_tree().process_frame
	await get_tree().process_frame
