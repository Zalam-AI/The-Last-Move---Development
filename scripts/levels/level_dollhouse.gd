extends PropertyBase
## PROPERTY 03 - THE DOLLHOUSE (ASHGROVE MANOR)
##
## A Victorian mansion with a grand staircase and 411 dolls. The dolls only move when
## nobody is looking at them, which is a rule the crew will learn to exploit -- and then
## abuse -- while carrying a piano down a staircase. Contracted dolls are always
## recoverable: they relocate to predefined safe positions, never into geometry.

const H := 3.05
const H2 := 3.0     # first floor height offset
const FLOOR2 := 3.05
const T := 0.2

var _dolls: Array[Furniture] = []
var _doll_timer := 6.0
var _safe_spots: Array[Vector3] = []
var _big_doll_seen := false
var _doll_cursor := 0


func build() -> void:
	wall_color = Color("#6f6157")
	floor_color = Color("#4a3a2e")
	ceiling_color = Color("#a89880")
	LevelKit.ground_plane(self, 110.0, Color("#1d2220"), 0.0)
	_build_ground_floor()
	_build_upper_floor()
	_build_stairs()
	_build_doors()
	_build_lighting()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 16.4), Vector3(1.4, 1.2, 8.4))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 13.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 8.6)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 0.1, 9.4)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.2, 0.1, 9.4)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 10.6)),
	]
	event_pool = ["doll_move", "light_flicker", "door_close", "doll_appear", "light_flicker"]


func _build_ground_floor() -> void:
	var wc := Color("#7d6f62")
	# footprint x -14..14, z -9..8
	add_floor(Rect2(-14, -9, 28, 17))
	# big hall down the middle, rooms either side
	LevelKit.wall(geo, Vector3(-5, 0, -2), Vector3(-5, 0, 8), H, T, wc,
		[{"center": 6.0, "width": 1.1, "height": 2.3}])
	LevelKit.wall(geo, Vector3(5, 0, -2), Vector3(5, 0, 8), H, T, wc,
		[{"center": 6.0, "width": 1.1, "height": 2.3}])
	LevelKit.wall(geo, Vector3(-14, 0, 0), Vector3(14, 0, 0), H, T, wc,
		[{"center": 9.0, "width": 1.15, "height": 2.3}, {"center": 19.0, "width": 1.15, "height": 2.3}])
	LevelKit.wall(geo, Vector3(-5, 0, -9), Vector3(-5, 0, 0), H, T, wc, [{"center": 4.5, "width": 1.1, "height": 2.3}])
	LevelKit.wall(geo, Vector3(5, 0, -9), Vector3(5, 0, 0), H, T, wc, [{"center": 4.5, "width": 1.1, "height": 2.3}])
	# exterior
	add_wall(Vector3(-14, 0, 8), Vector3(14, 0, 8), H, T, [{"center": 14.0, "width": 1.3, "height": 2.4}], wc)
	add_wall(Vector3(-14, 0, -9), Vector3(14, 0, -9), H, T, [], wc)
	add_wall(Vector3(-14, 0, -9), Vector3(-14, 0, 8), H, T, [], wc)
	add_wall(Vector3(14, 0, -9), Vector3(14, 0, 8), H, T, [], wc)
	# ceiling of ground floor leaves a stairwell hole over x -1..1.2, z -1..4
	LevelKit.ceiling_rect(geo, Rect2(-14, -9, 28, 8.0), FLOOR2, ceiling_color)
	LevelKit.ceiling_rect(geo, Rect2(-14, 4.0, 28, 4.0), FLOOR2, ceiling_color)
	# floor finishes
	geo.box(Vector3(9.0, 0.02, 8.0), Vector3(-9.5, 0.012, 4.0), Color("#4c3a2c"))
	geo.box(Vector3(9.0, 0.02, 8.0), Vector3(9.5, 0.012, 4.0), Color("#4c3a2c"))
	geo.box(Vector3(10.0, 0.02, 17.0), Vector3(0, 0.012, -0.5), Color("#3a2c22"))
	geo.box(Vector3(4.0, 0.02, 12.0), Vector3(0, 0.02, 2.0), Color("#6b4a33"))


func _build_upper_floor() -> void:
	var wc := Color("#786a5d")
	# upstairs footprint x -14..14, z -2..6  (stairwell hole at x -1..1.2, z 0..4)
	LevelKit.floor_rect(geo, Rect2(-14, -2, 13, 8), FLOOR2, floor_color)
	LevelKit.floor_rect(geo, Rect2(1.2, -2, 12.8, 8), FLOOR2, floor_color)
	LevelKit.floor_rect(geo, Rect2(-1, 4, 2.2, 2), FLOOR2, floor_color)
	LevelKit.ceiling_rect(geo, Rect2(-14, -2, 28, 8), FLOOR2 + H2, ceiling_color)
	LevelKit.wall(geo, Vector3(-14, FLOOR2, -2), Vector3(14, FLOOR2, -2), H2, T, wc, [])
	LevelKit.wall(geo, Vector3(-14, FLOOR2, 6), Vector3(14, FLOOR2, 6), H2, T, wc, [])
	LevelKit.wall(geo, Vector3(-14, FLOOR2, -2), Vector3(-14, FLOOR2, 6), H2, T, wc, [])
	LevelKit.wall(geo, Vector3(14, FLOOR2, -2), Vector3(14, FLOOR2, 6), H2, T, wc, [])
	LevelKit.wall(geo, Vector3(-5, FLOOR2, -2), Vector3(-5, FLOOR2, 6), H2, T, wc,
		[{"center": 6.0, "width": 1.1, "height": 2.2}])
	LevelKit.wall(geo, Vector3(5, FLOOR2, -2), Vector3(5, FLOOR2, 6), H2, T, wc,
		[{"center": 6.0, "width": 1.1, "height": 2.2}])
	# gallery railing around the stairwell
	LevelKit.railing(geo, Vector3(-1, FLOOR2, -2), Vector3(-1, FLOOR2, 4), 1.0, Color("#5a4432"))
	LevelKit.railing(geo, Vector3(1.2, FLOOR2, 4), Vector3(1.2, FLOOR2, -2), 1.0, Color("#5a4432"))


func _build_stairs() -> void:
	LevelKit.stairs(geo, Vector3(0.1, 0, 4.2), Vector3(0.1, FLOOR2, -1.4), 2.0, Color("#5a4432"), 16)
	LevelKit.railing(geo, Vector3(-0.9, 0, 4.2), Vector3(-0.9, FLOOR2, -1.4), 0.95, Color("#4a3626"))
	LevelKit.railing(geo, Vector3(1.1, 0, 4.2), Vector3(1.1, FLOOR2, -1.4), 0.95, Color("#4a3626"))


func _build_doors() -> void:
	add_door(Vector3(-0.65, 0, 8), 0.0, 1.3, 2.4, "Front Door", false, Color("#4a3527"))
	add_door(Vector3(-5, 0, 1.4), -PI * 0.5, 1.1, 2.3, "Drawing Room", false, Color("#6b4a33"))
	add_door(Vector3(5, 0, 1.4), -PI * 0.5, 1.1, 2.3, "Dining Room", false, Color("#6b4a33"))
	add_door(Vector3(-9.6, 0, 0), 0.0, 1.15, 2.3, "Library", false, Color("#6b4a33"))
	add_door(Vector3(8.5, 0, 0), 0.0, 1.15, 2.3, "Kitchen", false, Color("#6b4a33"))
	add_door(Vector3(-5, FLOOR2, 4.0), -PI * 0.5, 1.1, 2.2, "Nursery", false, Color("#6b4a33"))
	add_door(Vector3(5, FLOOR2, 4.0), -PI * 0.5, 1.1, 2.2, "Bedroom", false, Color("#6b4a33"))


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.4, Color(0.5, 0.6, 0.95), Vector3(-0.9, 0.55, 0.1))
	var l := add_light(Vector3(0, FLOOR2 - 0.4, 3.0), Color(1.0, 0.82, 0.58), 2.4, 12.0, true)
	register_flicker_light(l)
	add_light(Vector3(-9.5, FLOOR2 - 0.4, 4.0), Color(1.0, 0.78, 0.55), 1.6, 9.0, true)
	add_light(Vector3(9.5, FLOOR2 - 0.4, 4.0), Color(1.0, 0.78, 0.55), 1.6, 9.0, true)
	add_light(Vector3(-9.5, FLOOR2 - 0.4, -4.5), Color(0.85, 0.9, 1.0), 1.2, 8.0)
	add_light(Vector3(9.5, FLOOR2 - 0.4, -4.5), Color(1.0, 0.9, 0.72), 1.2, 8.0)
	add_light(Vector3(0, FLOOR2 + H2 - 0.35, 2.0), Color(1.0, 0.85, 0.62), 2.0, 11.0, true)
	add_light(Vector3(-9.5, FLOOR2 + H2 - 0.35, 2.0), Color(1.0, 0.8, 0.58), 1.3, 8.0)
	add_light(Vector3(9.5, FLOOR2 + H2 - 0.35, 2.0), Color(1.0, 0.8, 0.58), 1.3, 8.0)
	add_light(Vector3(0, 2.6, 8.6), Color(1.0, 0.84, 0.6), 1.4, 8.0, true)


func _build_furniture() -> void:
	# drawing room
	add_required(["piano_upright", "organ"], Vector3(-9.5, 0.03, 6.2), 0.0, "drawing")
	add_decor("sofa_two", Vector3(-12.4, 0.03, 3.0), PI * 0.5, "drawing")
	add_decor("armchair", Vector3(-7.0, 0.03, 3.0), -PI * 0.5, "drawing")
	add_decor("coffee_table", Vector3(-9.6, 0.03, 3.2), 0.0, "drawing")
	add_optional(["gramophone"], Vector3(-13.2, 0.03, 6.6), 0.0, "drawing", 0.7)

	# dining room
	add_required(["dining_table"], Vector3(9.5, 0.03, 4.0), 0.0, "dining")
	add_required(["dining_chair", "stool"], Vector3(8.5, 0.03, 3.2), 0.4, "dining")
	add_required(["dining_chair", "stool"], Vector3(10.5, 0.03, 3.2), -0.4, "dining")
	add_required(["dining_chair", "stool"], Vector3(8.5, 0.03, 4.8), 2.6, "dining")
	add_required(["dining_chair", "stool"], Vector3(10.5, 0.03, 4.8), -2.6, "dining")
	add_decor("sideboard", Vector3(13.2, 0.03, 6.4), -PI * 0.5, "dining")

	# library
	add_required(["bookshelf"], Vector3(-12.9, 0.03, -6.0), PI * 0.5, "library")
	add_required(["bookshelf_small"], Vector3(-6.4, 0.03, -6.4), -PI * 0.5, "library")
	add_decor("desk", Vector3(-9.5, 0.03, -4.0), 0.0, "library")
	add_decor("books_stack", Vector3(-9.5, 0.78, -4.0), 0.5, "library")
	add_decor("grandfather_clock", Vector3(-13.2, 0.03, -1.2), PI * 0.5, "library")

	# kitchen
	add_decor("kitchen_counter", Vector3(7.6, 0.03, -7.8), 0.0, "kitchen")
	add_decor("stove", Vector3(10.4, 0.03, -7.8), PI, "kitchen")
	add_decor("refrigerator", Vector3(13.2, 0.03, -4.0), -PI * 0.5, "kitchen")

	# hall
	add_decor("table_lamp", Vector3(-3.6, 0.03, 6.8), 0.0, "hall")
	add_decor("mirror_tall", Vector3(3.6, 0.03, 6.8), 0.0, "hall")
	add_required(["mirror_cursed"], Vector3(3.4, 0.03, 0.6), -PI * 0.5, "hall")

	# upstairs
	add_required(["wardrobe_antique", "wardrobe"], Vector3(13.0, FLOOR2 + 0.03, 2.0), -PI * 0.5, "bedroom")
	add_decor("bed_frame", Vector3(9.0, FLOOR2 + 0.03, 0.6), 0.0, "bedroom")
	add_decor("mattress", Vector3(9.0, FLOOR2 + 0.6, 0.6), 0.0, "bedroom")
	add_required(["dresser"], Vector3(6.4, FLOOR2 + 0.03, 0.4), PI * 0.5, "bedroom")
	add_decor("bed_frame", Vector3(-9.5, FLOOR2 + 0.03, 0.6), 0.0, "nursery")
	add_decor("mattress", Vector3(-9.5, FLOOR2 + 0.6, 0.6), 0.0, "nursery")
	add_required(["doll_large"], Vector3(-7.0, FLOOR2 + 0.03, 3.6), 0.0, "nursery")
	add_decor("toy_bear", Vector3(-11.5, FLOOR2 + 0.03, 3.6), 0.4, "nursery")
	add_required(["doll_porcelain"], Vector3(-12.0, FLOOR2 + 0.03, 1.2), 0.0, "nursery")
	add_required(["doll_porcelain"], Vector3(-11.4, FLOOR2 + 0.03, 1.4), 0.0, "nursery")
	add_decor("doll_porcelain", Vector3(-10.8, FLOOR2 + 0.03, 1.2), 0.0, "nursery")
	add_decor("doll_porcelain", Vector3(-10.2, FLOOR2 + 0.03, 1.4), 0.0, "nursery")
	add_decor("doll_porcelain", Vector3(2.6, FLOOR2 + 0.03, 5.2), 0.0, "landing")
	add_decor("doll_porcelain", Vector3(3.1, FLOOR2 + 0.03, 5.4), 0.0, "landing")

	_safe_spots = [
		Vector3(-9.5, FLOOR2 + 0.05, 2.4), Vector3(-7.4, FLOOR2 + 0.05, 5.2),
		Vector3(-11.5, FLOOR2 + 0.05, 5.2), Vector3(-9.5, FLOOR2 + 0.05, 4.6),
		Vector3(2.6, FLOOR2 + 0.05, 2.0), Vector3(-2.6, FLOOR2 + 0.05, 2.0),
		Vector3(-9.5, 0.05, 5.0), Vector3(9.5, 0.05, 6.0), Vector3(0, 0.05, 6.6),
		Vector3(-2.0, 0.05, 2.0), Vector3(2.0, 0.05, 2.0),
	]


func on_mission_start(m: MissionManager) -> void:
	Audio.play_ambience("mansion_creak", 2.5)
	Audio.play_music("prop_uneasy", 3.0)
	_dolls.clear()
	for f in m.furniture:
		if is_instance_valid(f) and str(f.item_id).begins_with("doll"):
			_dolls.append(f)
			f.picked_up.connect(_on_doll_touched.bind(f))
			f.dropped.connect(_on_doll_dropped)


func _on_doll_touched(_holders: Array, f: Furniture) -> void:
	Audio.play_sfx("whisper", f.global_position, -2.0)
	mission_notify("The doll is warm. Log it on form 12-B.")
	if mission:
		mission.trigger_event("doll_disturbed", {"pos": f.global_position})


func _on_doll_dropped() -> void:
	Audio.play_sfx("doll_drop", Vector3.ZERO, -6.0)


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host() or m.state != MissionManager.MState.ACTIVE:
		return
	_doll_timer -= delta
	if _doll_timer > 0.0:
		return
	_doll_timer = rng.randf_range(4.5, 8.0)
	_move_unobserved_dolls(m)


func _move_unobserved_dolls(m: MissionManager) -> void:
	var moved := 0
	# stagger: at most three dolls are evaluated per tick, round-robin, so one frame
	# never carries a dozen raycasts and a dozen teleports at once
	var considered := 0
	var total := _dolls.size()
	if total == 0:
		return
	for i in total:
		var idx := (_doll_cursor + i) % total
		var f: Furniture = _dolls[idx]
		if considered >= 3:
			break
		considered += 1
		if not is_instance_valid(f) or f.is_held() or f.delivered or not f.is_alive:
			continue
		if _is_watched(f.global_position):
			continue
		var options: Array[Vector3] = []
		for spot in _safe_spots:
			# never teleport next to a player: the fun is in *not* seeing it happen
			var too_close := false
			for pid in Net.players.keys():
				var p := Game.get_player(int(pid))
				if p and p.global_position.distance_to(spot) < 3.5:
					too_close = true
					break
			if not too_close and spot.distance_to(f.global_position) > 1.5:
				options.append(spot)
		if options.is_empty():
			continue
		var dest: Vector3 = options[rng.randi() % options.size()]
		f.global_position = dest
		f.linear_velocity = Vector3.ZERO
		f.angular_velocity = Vector3.ZERO
		moved += 1
		Audio.play_sfx("doll_move", dest, -14.0)
	_doll_cursor = (_doll_cursor + considered) % maxi(1, total)
	if moved > 0 and not _big_doll_seen:
		_big_doll_seen = true
		m.trigger_event("doll_appear", {})


func _is_watched(pos: Vector3) -> bool:
	for pid in Net.players.keys():
		var p := Game.get_player(int(pid))
		if p == null or p.camera == null:
			continue
		if p.is_downed:
			continue
		var to := pos - p.camera.global_position
		if to.length() > 26.0:
			continue
		var fwd := -p.camera.global_transform.basis.z
		if fwd.dot(to.normalized()) < 0.62:
			continue
		# line of sight
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, pos + Vector3.UP * 0.3)
		q.collision_mask = Layers.WORLD | Layers.DOOR
		if space.intersect_ray(q).is_empty():
			return true
	return false


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"doll_move":
			_move_unobserved_dolls(m)
		"doll_appear":
			Audio.play_sfx("whisper", data.get("pos", Vector3.ZERO), -4.0)
			mission_notify("A doll has appeared in a room where there was no doll.")
		_:
			super(m, event_name, data)


func on_loud_noise(m: MissionManager, pos: Vector3) -> void:
	Audio.play_sfx("doll_move", pos, -6.0)
	_move_unobserved_dolls(m)
