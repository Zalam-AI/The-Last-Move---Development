extends PropertyBase
## PROPERTY 08 - THE LAST CUSTOMER
##
## The final contract. A rotunda with four wings and a vault below it. The house uses
## everything the crew has learned: the wings shift like the Endless House, things watch
## from the dark like the Dollhouse, and the architecture breathes like the seventh
## property. The contract is one object, and it is not furniture.

const H := 3.6
const T := 0.26
const WING_SPACING := 26.0

var _rooms: Array[Dictionary] = []
var _perm: Array[int] = [0, 1, 2, 3]
var _watcher: Node3D
var _watcher_timer := 12.0
var _shuffle_timer := 60.0
var _crate: Furniture = null
var _reveal_stage := 0
var _breath := 0.0


func build() -> void:
	wall_color = Color("#43364a")
	floor_color = Color("#2e2632")
	ceiling_color = Color("#514060")
	LevelKit.ground_plane(self, 150.0, Color("#12100f"), 0.0)
	_build_rotunda()
	_build_wings()
	_build_vault()
	_build_portals()
	_build_watcher()
	_build_lighting()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 21.4), Vector3(1.4, 1.2, 10.4))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 18.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 10.6)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.4, 0.1, 11.4)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.4, 0.1, 11.4)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 12.6)),
	]
	event_pool = ["shuffle_rooms", "watcher", "breath", "light_flicker", "shuffle_rooms", "whisper_event"]


func _build_rotunda() -> void:
	# circular-ish rotunda approximated with 12 wall segments
	var radius := 9.0
	var segments := 12
	var wc := wall_color
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var openings: Array = []
		if i == 2:
			openings = [{"center": (p1 - p0).length() * 0.5, "width": 2.2, "height": 2.9}]   # to the wings
		if i == 8:
			openings = [{"center": (p1 - p0).length() * 0.5, "width": 2.4, "height": 3.0}]
		if i == 4:
			openings = [{"center": (p1 - p0).length() * 0.5, "width": 1.4, "height": 2.5}]
		LevelKit.wall(geo, p0, p1, H, T, wc, openings)
	add_floor(Rect2(-11, -11, 22, 22))
	LevelKit.ceiling_rect(geo, Rect2(-11, -11, 22, 22), H, ceiling_color)
	# inlaid floor pattern
	for i in 3:
		geo.cyl(8.0 - i * 2.4, 8.0 - i * 2.4, 0.02, Vector3(0, 0.012 + i * 0.004, 0),
			[Color("#3a2c3c"), Color("#4a3848"), Color("#2a2030")][i], MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 24)
	# dais in the centre
	geo.cyl(2.4, 2.8, 0.35, Vector3(0, 0.175, 0), Color("#5a4a5e"), MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 20)


func _build_wings() -> void:
	var names := ["THE OFFICE", "THE NURSERY", "THE GALLEY", "THE CHAPEL"]
	for i in 4:
		var center := Vector3(0, 0, 0)
		match i:
			0: center = Vector3(0, 0, -WING_SPACING - 9.0)
			1: center = Vector3(0, 0, WING_SPACING + 9.0)
			2: center = Vector3(-WING_SPACING - 9.0, 0, 0)
			3: center = Vector3(WING_SPACING + 9.0, 0, 0)
		var entry := _build_wing(center, names[i], i)
		_rooms.append({"name": names[i], "entry": entry, "center": center})


func _build_wing(center: Vector3, wing_name: String, index: int) -> Transform3D:
	var w := 14.0
	var d := 12.0
	var wc := wall_color.darkened(0.04 * index)
	var rect := Rect2(center.x - w * 0.5, center.z - d * 0.5, w, d)
	add_floor(rect)
	LevelKit.ceiling_rect(geo, rect, H, ceiling_color)
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z - d * 0.5), Vector3(center.x + w * 0.5, 0, center.z - d * 0.5), H, T, wc, [])
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z + d * 0.5), Vector3(center.x + w * 0.5, 0, center.z + d * 0.5), H, T, wc, [])
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z - d * 0.5), Vector3(center.x - w * 0.5, 0, center.z + d * 0.5), H, T, wc, [])
	LevelKit.wall(geo, Vector3(center.x + w * 0.5, 0, center.z - d * 0.5), Vector3(center.x + w * 0.5, 0, center.z + d * 0.5), H, T, wc, [])
	# doorway facing inwards
	var door_side := Vector3.ZERO
	match index:
		0: door_side = Vector3(0, 0, d * 0.5)
		1: door_side = Vector3(0, 0, -d * 0.5)
		2: door_side = Vector3(w * 0.5, 0, 0)
		3: door_side = Vector3(-w * 0.5, 0, 0)
	var doorway_center := center + door_side
	LevelKit.door_frame(geo, doorway_center, 2.2, 2.8, 0.0 if index < 2 else PI * 0.5, wc)
	add_light(center + Vector3(0, H - 0.45, 0), Color(0.85, 0.7, 1.0), 1.5, 13.0, index % 2 == 0)
	add_light(center + Vector3(0, 1.4, 0), Color(1.0, 0.5, 0.5), 0.5, 5.0)
	var facing := PI
	match index:
		1: facing = 0.0
		2: facing = -PI * 0.5
		3: facing = PI * 0.5
	return Transform3D(Basis(Vector3.UP, facing), doorway_center + (door_side.normalized() * -1.6))


func _build_vault() -> void:
	# a small lower vault under the dais, reached by a stair behind the rotunda
	var y := -3.4
	LevelKit.floor_rect(geo, Rect2(-6, -6, 12, 12), y, Color("#221a24"))
	LevelKit.ceiling_rect(geo, Rect2(-6, -6, 12, 12), y + 2.8, Color("#2e2430"))
	LevelKit.wall(geo, Vector3(-6, y, 6), Vector3(6, y, 6), 2.8, T, Color("#3a2c3e"), [])
	LevelKit.wall(geo, Vector3(-6, y, -6), Vector3(6, y, -6), 2.8, T, Color("#3a2c3e"), [])
	LevelKit.wall(geo, Vector3(-6, y, -6), Vector3(-6, y, 6), 2.8, T, Color("#3a2c3e"), [])
	LevelKit.wall(geo, Vector3(6, y, -6), Vector3(6, y, 6), 2.8, T, Color("#3a2c3e"), [])
	LevelKit.stairs(geo, Vector3(0, y, -6.0), Vector3(0, 0, -2.0), 1.8, Color("#41364a"), 18)
	add_light(Vector3(0, y + 2.3, 0), Color(1.0, 0.45, 0.45), 1.6, 9.0, true)


func _build_portals() -> void:
	# the wings are not where they appear to be
	for i in 4:
		var entry: Transform3D = _rooms[i]["entry"]
		add_portal(entry.origin + Vector3(0, 1.1, 0) - entry.basis.z * -1.0, Vector3(2.4, 2.6, 1.4), _rooms[_perm[i]]["entry"])
		# and the rotunda's wing doors take you somewhere else entirely
	var rotunda_doors := [
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, -8.4)),
		Transform3D(Basis(Vector3.UP, 0), Vector3(0, 0.1, 8.4)),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-8.4, 0.1, 0)),
		Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(8.4, 0.1, 0)),
	]
	for i in 4:
		add_portal(rotunda_doors[i].origin + Vector3(0, 1.1, 0), Vector3(2.4, 2.6, 1.6), _rooms[_perm[i]]["entry"])


func _refresh_portals() -> void:
	for i in 4:
		if i < portal_count():
			set_portal_target(i, _rooms[_perm[i]]["entry"])


func _shuffle_wings() -> void:
	var fresh: Array[int] = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: int = fresh[i]
		fresh[i] = fresh[j]
		fresh[j] = t
	_perm = fresh
	_refresh_portals()
	Audio.play_sfx("house_react", Vector3.ZERO, -2.0)
	mission_notify("The wings of the house have moved. The contract has not.")


func _build_watcher() -> void:
	_watcher = Node3D.new()
	_watcher.name = "Watcher"
	var b := MeshBuilder.new()
	b.cyl(0.22, 0.5, 1.9, Vector3(0, 0.95, 0), Color("#0a0a0c"), MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 8)
	b.sphere(0.22, Vector3(0, 2.0, 0), Color("#0a0a0c"), MeshBuilder.Mat.PLAIN, false, 0.36)
	b.sphere(0.05, Vector3(-0.08, 2.02, 0.18), Color(0.9, 0.85, 0.6), MeshBuilder.Mat.EMISSIVE, false)
	b.sphere(0.05, Vector3(0.08, 2.02, 0.18), Color(0.9, 0.85, 0.6), MeshBuilder.Mat.EMISSIVE, false)
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	_watcher.add_child(mi)
	_watcher.position = Vector3(0, 0, -14)
	_watcher.visible = false
	add_child(_watcher)


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.2, Color(0.6, 0.45, 0.85), Vector3(-0.95, 0.5, 0.15))
	var l := add_light(Vector3(0, H - 0.5, 0), Color(0.9, 0.72, 1.0), 2.6, 16.0, true)
	register_flicker_light(l)
	add_light(Vector3(0, 1.4, -6.0), Color(1.0, 0.5, 0.5), 0.8, 7.0)
	add_light(Vector3(0, 2.6, 6.0), Color(0.9, 0.8, 1.0), 0.8, 7.0)
	add_light(Vector3(0, 2.6, 18.6), Color(0.9, 0.9, 1.0), 1.4, 10.0, true)


func _build_furniture() -> void:
	# rotunda: the dais holds the crate
	add_required(["last_crate"], Vector3(0, 0.42, 0), 0.4, "rotunda")
	add_decor("grandfather_clock", Vector3(-6.0, 0.03, 6.0), -PI * 0.75, "rotunda")
	add_decor("grandfather_clock", Vector3(6.0, 0.03, 6.0), PI * 0.75, "rotunda")
	add_decor("mirror_cursed", Vector3(0, 0.03, 8.2), PI, "rotunda")

	# wings
	var w0: Vector3 = _rooms[0]["center"]
	var w1: Vector3 = _rooms[1]["center"]
	var w2: Vector3 = _rooms[2]["center"]
	var w3: Vector3 = _rooms[3]["center"]

	add_required(["piano_grand"], w0 + Vector3(-4.0, 0.03, -3.4), 0.0, "office")
	add_decor("desk", w0 + Vector3(3.0, 0.03, -3.6), 0.0, "office")
	add_decor("bookshelf", w0 + Vector3(-6.4, 0.03, 3.0), PI * 0.5, "office")
	add_decor("doll_porcelain", w0 + Vector3(4.0, 0.03, 2.0), 0.0, "office")

	add_required(["doll_large"], w1 + Vector3(-3.0, 0.03, 2.0), 0.0, "nursery")
	add_decor("doll_porcelain", w1 + Vector3(0.0, 0.03, 3.4), 0.0, "nursery")
	add_decor("doll_porcelain", w1 + Vector3(0.6, 0.03, 3.6), 0.0, "nursery")
	add_decor("toy_bear", w1 + Vector3(-5.0, 0.03, -3.0), 0.0, "nursery")
	add_required(["wardrobe_antique"], w1 + Vector3(5.6, 0.03, -3.4), 0.0, "nursery")

	add_required(["sideboard"], w2 + Vector3(-4.0, 0.03, -4.0), PI * 0.5, "galley")
	add_decor("kitchen_counter", w2 + Vector3(3.0, 0.03, 4.6), PI, "galley")
	add_decor("stove", w2 + Vector3(6.0, 0.03, 4.6), PI, "galley")

	add_required(["organ"], w3 + Vector3(0.0, 0.03, -4.0), 0.0, "chapel")
	add_required(["mirror_tall"], w3 + Vector3(-4.6, 0.03, 2.0), PI * 0.5, "chapel")
	add_optional(["gramophone"], w3 + Vector3(4.4, 0.03, 2.4), 0.0, "chapel", 0.8)

	# vault
	add_optional(["container_strange"], Vector3(4.0, -3.37, 4.0), 0.0, "vault", 0.9)
	add_decor("crate", Vector3(-4.0, -3.37, 4.0), 0.3, "vault")
	add_decor("suitcase", Vector3(-4.6, -3.37, 2.4), 0.2, "vault")


func on_mission_start(_m: MissionManager) -> void:
	Audio.play_ambience("last_customer", 2.5)
	Audio.play_music("prop_dread", 2.0)
	Audio.play_voice("training_04", "PA: The customer is waiting. The customer has always been waiting.", -3.0)
	_refresh_portals()


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host():
		return
	_breath += delta
	_shuffle_timer -= delta
	if _shuffle_timer <= 0.0:
		_shuffle_timer = 75.0
		_shuffle_wings()
	_watcher_timer -= delta
	if _watcher_timer <= 0.0:
		_watcher_timer = rng.randf_range(20.0, 40.0)
		_spawn_watcher(m)
	if _watcher and _watcher.visible:
		var nearest := 999.0
		for pid in Net.players.keys():
			var p := Game.get_player(int(pid))
			if p:
				nearest = minf(nearest, p.global_position.distance_to(_watcher.global_position))
		if nearest < 7.0:
			_watcher.visible = false
			Audio.play_sfx("whisper", _watcher.global_position, -6.0)
	# narrative beats as the contract progresses
	if _reveal_stage == 0 and m.required_delivered >= 1:
		_reveal_stage = 1
		Game.ui.show_subtitle("The crate is lighter than it should be. Something inside shifts when you stop walking.", 6.0)
		Audio.play_voice("training_03", "", -8.0)
	if _reveal_stage == 1 and m.required_delivered >= m.required_total and m.required_total > 0:
		_reveal_stage = 2
		Game.ui.show_subtitle("Dispatch: 'Good. Now bring it home. The customer is very close.'", 6.0)


func _spawn_watcher(m: MissionManager) -> void:
	var angle := rng.randf() * TAU
	var dist := rng.randf_range(12.0, 18.0)
	var dir := Vector3(cos(angle), 0, sin(angle))
	# place it in whichever wing a player is NOT in
	var best: Vector3 = _rooms[0]["center"]
	var best_score := -1.0
	for room in _rooms:
		var c: Vector3 = room["center"]
		var nearest := 999.0
		for pid in Net.players.keys():
			var p := Game.get_player(int(pid))
			if p:
				nearest = minf(nearest, p.global_position.distance_to(c))
		if nearest > best_score:
			best_score = nearest
			best = c
	_watcher.global_position = best + dir * dist + Vector3(0, 0.05, 0)
	_watcher.visible = true
	Audio.play_sfx("whisper", _watcher.global_position, -4.0)
	m.trigger_event("watcher_seen", {"pos": _watcher.global_position})


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shuffle_rooms":
			_shuffle_wings()
		"watcher":
			_spawn_watcher(m)
		"breath":
			Audio.play_sfx("house_react", data.get("pos", Vector3.ZERO), -2.0)
			mission_notify("The house exhales. The floor moves with it.")
		"whisper_event":
			Audio.play_sfx("whisper", Vector3(rng.randf_range(-6, 6), 1.5, rng.randf_range(-6, 6)), -6.0)
			shuffle_small_objects(m)
		_:
			super(m, event_name, data)


func on_loud_noise(m: MissionManager, pos: Vector3) -> void:
	Audio.play_sfx("house_react", pos, -3.0)
	if rng.randf() < 0.5:
		_spawn_watcher(m)
