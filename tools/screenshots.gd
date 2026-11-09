extends Node
## Screenshot / visual-audit harness.
##
## Runs the real game with a real renderer and writes PNGs. Used both as an audit tool
## (look at what the game actually renders) and to produce the release store screenshots.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan \
##     res://tools/screenshots.tscn -- --out=/home/user/shots --shots=willow --mode=audit
##
## Modes:
##   store  (default) menus, headquarters, one exterior and one interior per property
##   audit  plan views + multi-angle eye-level views per property, plus a HUD shot
##   one    a single free-camera shot, coordinates from --pos=x,y,z --look=x,y,z

var out_dir := "user://shots"
var only: Array[String] = []
var mode := "store"
var free_pos := Vector3.ZERO
var free_look := Vector3.ZERO
var _cam: Camera3D


func _ready() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	await get_tree().process_frame
	if mode == "one":
		await _shot_free(only[0] if not only.is_empty() else "free")
		get_tree().quit()
		return
	if only.is_empty() or only.has("menu"):
		await _shot_menu()
	if only.is_empty() or only.has("hq"):
		await _shot_hq()
	for pid in ["willow", "endless", "dollhouse", "sinking", "perfect", "hotel", "breathing", "last_customer"]:
		if only.is_empty() or only.has(pid):
			await _shot_property(pid)
	if mode == "audit" and (only.is_empty() or only.has("hud")):
		await _shot_hud()
	print("[shots] done -> %s" % out_dir)
	get_tree().quit()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--shots="):
			for s in a.trim_prefix("--shots=").split(",", false):
				only.append(s)
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--pos="):
			free_pos = _vec(a.trim_prefix("--pos="))
		elif a.begins_with("--look="):
			free_look = _vec(a.trim_prefix("--look="))


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("[shots] %s %dx%d %s" % [path, img.get_width(), img.get_height(), "ok" if err == OK else "FAILED"])


func _settle(frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame


# ---------------------------------------------------------------- free camera ---

func _free_cam(pos: Vector3, look: Vector3) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.fov = 76.0
		_cam.near = 0.05
		_cam.far = 400.0
		get_tree().root.add_child(_cam)
	_cam.current = true
	_cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		_cam.look_at(look, Vector3.UP)
	await _settle(10)


func _shot_free(name: String) -> void:
	await _free_cam(free_pos, free_look)
	await _capture(name)


# ------------------------------------------------------------------- shots ---

func _shot_menu() -> void:
	Game.go_to_menu()
	await _settle(20)
	await _capture("00_main_menu")
	Game.ui.show_lobby_panel(true)
	await _settle(10)
	await _capture("01_lobby")
	Game.ui.close_all_panels()


func _shot_hq() -> void:
	Game.start_solo()
	await get_tree().process_frame
	Game.enter_headquarters()
	await _settle(24)
	for i in 3:
		var p := Game.local_player()
		if p == null:
			break
		var spots := [Vector3(0, 1.7, 6.0), Vector3(-6, 1.7, -2.0), Vector3(9.0, 1.7, 3.0)]
		var looks := [Vector3(0, 2.2, -11.0), Vector3(-13, 1.2, -7.0), Vector3(12, 1.2, -6.0)]
		p.global_position = spots[i] - Vector3(0, 1.62, 0)
		_look(p, looks[i])
		await _settle(16)
		await _capture("02_headquarters_%d" % i)
	Game.ui.open_shop()
	await _settle(10)
	await _capture("03_shop")
	Game.ui.close_all_panels()
	await _settle(6)


func _shot_property(pid: String) -> void:
	if Game.state == Game.State.MENU or Game.state == Game.State.BOOT:
		Game.start_solo()
		await _settle(4)
	Save.profile["unlocked_properties"] = ["willow", "endless", "dollhouse", "sinking",
		"perfect", "hotel", "breathing", "last_customer"]
	Game.start_mission(pid, 1234, [])
	await _settle(10)
	var m := Game.mission
	if m == null:
		print("[shots] %s: no mission" % pid)
		return
	Game.ui.close_all_panels()
	await _settle(24)
	var truck_pos: Vector3 = m.truck.global_position if m.truck != null else Vector3.ZERO
	if mode == "audit":
		# wide plan view from above the property, and an eye-level view from the truck side
		var centre := truck_pos * 0.5
		await _free_cam(centre + Vector3(0, 26.0, 24.0), centre)
		await _capture("10_%s_plan" % pid)
		await _free_cam(truck_pos + Vector3(0, 2.4, 8.0), truck_pos + Vector3(0, 1.0, -6.0))
		await _capture("11_%s_truck_side" % pid)
	else:
		var p := Game.local_player()
		if p != null and m.truck != null:
			p.global_position = m.truck.depart_point() + Vector3(0, 0.2, 0)
			_look(p, m.truck.global_position + Vector3(0, 1.5, 0))
			_cam = null
		await _settle(16)
		await _capture("10_%s_exterior" % pid)
	# interior: stand at the property centre at eye height looking at the hall
	# deepest interior item: furthest from the truck front, so the camera lands indoors
	var target: Furniture = null
	var best := -1.0
	var hub: Vector3 = m.truck.global_position if m.truck != null else Vector3.ZERO
	for f in m.furniture:
		if not is_instance_valid(f) or not f.is_required:
			continue
		var d := f.global_position.distance_to(hub)
		if d > best:
			best = d
			target = f
	if target != null:
		# pick a camera spot the physics says is clear of walls, in a ring around the item
		var reach := 2.2 + maxf(target.size.x, target.size.z) * 0.75
		var eye := _room_eye(target.global_position, reach)
		print("[shot] target=", target.item_id, " at ", target.global_position, " eye=", eye)
		await _free_cam(eye, target.global_position + Vector3(0, 0.6, 0))
		await _capture("12_%s_room" % pid)
		var eye2 := _room_eye(target.global_position, reach * 0.8, 1.15)
		await _free_cam(eye2, target.global_position + Vector3(0, 0.55, 0))
		await _capture("13_%s_room_b" % pid)
	Game.return_to_headquarters()
	await _settle(10)


## Finds a camera position `dist` metres from `at` with a clear line of sight, by probing a
## ring of eight directions with a real raycast. This is how the harness avoids shooting the
## inside of a wall in properties with many small rooms.
func _clear_eye(at: Vector3, dist: float, y_off := 1.62) -> Vector3:
	var space := get_viewport().world_3d.direct_space_state
	var eye_y := at.y + y_off - 0.7
	for i in 12:
		var a := TAU * float(i) / 12.0
		var cand := Vector3(at.x + cos(a) * dist, eye_y, at.z + sin(a) * dist)
		if space == null:
			return cand
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), cand, Layers.WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or cand.distance_to(hit["position"]) > dist * 0.9:
			return cand
	# nothing was clear: fall back to directly above the item looking down
	return at + Vector3(0, 2.4, 0)


## Room-shot camera. Prefers a clear eye that also *sees furniture*: candidates around the
## subject are scored by how many pieces are within a 70-degree cone in front of the camera and
## how close they are, so the frame lands on the room instead of on a bare blank wall.
func _room_eye(at: Vector3, dist: float, y_off := 1.62) -> Vector3:
	var pad := dist * 0.55
	var space := get_viewport().world_3d.direct_space_state
	var eye_y := at.y + y_off - 0.7
	var best_eye := at + Vector3(0, 2.4, 0)
	var best_score := -1.0
	var m := Game.mission
	for i in 12:
		var a := TAU * float(i) / 12.0
		var cand := Vector3(at.x + cos(a) * dist, eye_y, at.z + sin(a) * dist)
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.6, 0), cand, Layers.WORLD)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and cand.distance_to(hit["position"]) < dist * 0.9:
				continue
		# never stand inside architecture either: the sinking house is half underground and
		# shooting from inside its own earth shell produced a black frame
		if space != null:
			var pq := PhysicsPointQueryParameters3D.new()
			pq.position = cand
			pq.collision_mask = Layers.WORLD
			pq.collide_with_bodies = true
			if not space.intersect_point(pq, 1).is_empty():
				continue
		# never stand inside a piece of furniture: 13_ used to open on the inside of a bed
		var inside := false
		if m != null:
			for f in m.furniture:
				if not is_instance_valid(f):
					continue
				var p2 := f.global_position
				if absf(cand.x - p2.x) < f.size.x * 0.55 and absf(cand.z - p2.z) < f.size.z * 0.55 \
						and cand.y > p2.y - 0.2 and cand.y < p2.y + f.size.y * 1.15:
					inside = true
					break
		if inside:
			continue
		# reject candidates standing on a different storey: the line of sight may be clear down
		# a stairwell while the camera still ends up in a corridor instead of the room
		if space != null:
			var fl := PhysicsRayQueryParameters3D.create(cand, cand - Vector3(0, 3.0, 0), Layers.WORLD)
			var fh := space.intersect_ray(fl)
			if fh.is_empty() or absf((fh["position"] as Vector3).y - at.y) > 1.2:
				continue
		var look := (at - cand).normalized()
		# keep the camera out of the subject's own footprint, or a bed fills the whole frame
		if Vector2(cand.x - at.x, cand.z - at.z).length() < pad:
			continue
		var score := 0.0
		if m != null:
			for f in m.furniture:
				if not is_instance_valid(f):
					continue
				var d := f.global_position - cand
				var dd := d.length()
				if dd > 7.0 or dd < 0.4:
					continue
				if look.dot(d / dd) < 0.34:
					continue
				score += 1.0 + (7.0 - dd) * 0.2
		if score > best_score:
			best_score = score
			best_eye = cand
	return best_eye


func _shot_hud() -> void:
	if Game.state == Game.State.MENU or Game.state == Game.State.BOOT:
		Game.start_solo()
		await _settle(4)
	Game.start_mission("willow", 99, ["night_shift"])
	await _settle(10)
	var m := Game.mission
	if m == null:
		return
	Game.ui.close_all_panels()
	await _settle(30)
	Game.ui.notify("Contract loaded. Cargo counts while the bay doors are open.", "hint")
	if m.truck != null:
		m.truck.set_doors(true)
	var p := Game.local_player()
	if p != null:
		p.global_position = m.truck.depart_point() + Vector3(0, 0.3, 0)
		_look(p, Vector3(0, 1.6, 30.0))
		_cam = null
	await _settle(12)
	await _capture("20_hud")
	Game.return_to_headquarters()


func _look(p: Player, at: Vector3) -> void:
	var eye := p.global_position + Vector3(0, 1.62, 0)
	var d := at - eye
	if d.length() < 0.01:
		return
	p.rotation.y = atan2(-d.x, -d.z)
	if p.camera != null:
		p.camera.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
