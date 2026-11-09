extends PropertyBase
## PROPERTY 02 - THE ENDLESS HOUSE
##
## The exterior and the central hall are honest. The four doorways out of the hall are
## not: each one deposits you in one of four rooms that exist somewhere else entirely,
## and the mapping shuffles. The rooms are plain, believable Victorian rooms -- the horror
## is entirely in the routing. Every room always has a working way back to the hall, so a
## crew can never be permanently trapped; they can only be embarrassed.

const H := 2.85
const T := 0.2
const ROOM_SPACING := 70.0

var _rooms: Array[Dictionary] = []
var _hall_doors: Array[Transform3D] = []
var _perm: Array[int] = [0, 1, 2, 3]
var _shuffle_timer := 55.0
var _entry_door: Door


func build() -> void:
	wall_color = Color("#7d7466")
	floor_color = Color("#54453a")
	ceiling_color = Color("#b8b2a4")
	LevelKit.ground_plane(self, 120.0, Color("#20261f"), 0.0)
	_build_hall()
	_build_rooms()
	_build_portals()
	_build_lighting()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 14.4), Vector3(1.3, 1.2, 7.3))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 11.5))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 7.4)),
		Transform3D(Basis(Vector3.UP, 0.5), Vector3(-2.0, 0.1, 8.0)),
		Transform3D(Basis(Vector3.UP, -0.5), Vector3(2.0, 0.1, 8.0)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 9.2)),
	]
	event_pool = ["shuffle_rooms", "light_flicker", "door_close", "shuffle_rooms", "whisper_event"]


func _build_hall() -> void:
	add_floor(Rect2(-7, -7, 14, 14))
	add_ceiling(Rect2(-7, -7, 14, 14), H)
	var wc := Color("#8a8175")
	var arch := {"width": 1.5, "height": 2.3}
	add_wall(Vector3(-7, 0, 7), Vector3(7, 0, 7), H, T, [{"center": 7.0, "width": 1.2, "height": 2.15}], wc)
	add_wall(Vector3(-7, 0, -7), Vector3(7, 0, -7), H, T, [{"center": 7.0, "width": 1.5, "height": 2.3}], wc)
	add_wall(Vector3(-7, 0, -7), Vector3(-7, 0, 7), H, T, [{"center": 7.0, "width": 1.5, "height": 2.3}], wc)
	add_wall(Vector3(7, 0, -7), Vector3(7, 0, 7), H, T, [{"center": 7.0, "width": 1.5, "height": 2.3}], wc)
	_entry_door = add_door(Vector3(-0.6, 0, 7), 0.0, 1.2, 2.15, "Front Door", false, Color("#5f4632"))
	_entry_door.state_changed.connect(func(_o): _shuffle_rooms())

	# kitchen nook (east of the hall)
	geo.box(Vector3(0.2, H, 5.0), Vector3(4.0, H * 0.5, -2.0), wc)
	geo.box(Vector3(3.0, H, 0.2), Vector3(5.5, H * 0.5, 0.5), wc)
	geo.box(Vector3(6.0, 0.02, 6.0), Vector3(0, 0.01, 0), Color("#463c33"))
	geo.box(Vector3(2.6, 0.02, 12.0), Vector3(0, 0.015, 0), Color("#5a4a3a"))

	_hall_doors = [
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -6.0)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(6.0, 0.05, 0.0)),
		Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0.05, 6.0)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(-6.0, 0.05, 0.0)),
	]


func _build_rooms() -> void:
	var names := ["LIBRARY", "STUDIO", "NURSERY", "PARLOUR"]
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var center := Vector3(cos(angle), 0, sin(angle)) * ROOM_SPACING
		var entry := _build_room_module(center, names[i], i)
		_rooms.append({"name": names[i], "entry": entry, "center": center})


func _build_room_module(center: Vector3, room_name: String, index: int) -> Transform3D:
	var w := 9.0
	var d := 9.0
	var wc := Color("#84796b").darkened(0.05 * index)
	var rect := Rect2(center.x - w * 0.5, center.z - d * 0.5, w, d)
	add_floor(rect, center.y)
	add_ceiling(rect, center.y + H)
	# walls: doorway on the +Z side
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z + d * 0.5), Vector3(center.x + w * 0.5, 0, center.z + d * 0.5),
		H, T, wc, [{"center": w * 0.5, "width": 1.25, "height": 2.15}])
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z - d * 0.5), Vector3(center.x + w * 0.5, 0, center.z - d * 0.5), H, T, wc, [])
	LevelKit.wall(geo, Vector3(center.x - w * 0.5, 0, center.z - d * 0.5), Vector3(center.x - w * 0.5, 0, center.z + d * 0.5), H, T, wc, [])
	LevelKit.wall(geo, Vector3(center.x + w * 0.5, 0, center.z - d * 0.5), Vector3(center.x + w * 0.5, 0, center.z + d * 0.5), H, T, wc, [])
	geo.box(Vector3(w - 1.2, 0.02, d - 1.2), Vector3(center.x, 0.012, center.z), Color("#4d3f33"))
	add_light(center + Vector3(0, H - 0.3, 0), Color(1.0, 0.86, 0.66), 1.7, 8.0, index % 2 == 0)
	add_light(center + Vector3(0, 1.5, 2.4), Color(1.0, 0.8, 0.55), 0.6, 4.0)
	return Transform3D(Basis(Vector3.UP, PI), center + Vector3(0, 0.05, d * 0.5 - 0.9))


func _build_portals() -> void:
	# Hall -> room (mapping shuffles); room -> hall (always returns).
	for i in 4:
		var hd: Transform3D = _hall_doors[i]
		var target: Transform3D = _rooms[_perm[i]]["entry"]
		add_portal(hd.origin + Vector3(0, 1.1, 0), Vector3(1.6, 2.2, 1.0), target, ["", "", "", ""][i])
	for i in 4:
		var room: Dictionary = _rooms[i]
		var entry: Transform3D = room["entry"]
		# step back through the room's own doorway and you are in the hall again
		add_portal(entry.origin + entry.basis.z * 0.8 + Vector3(0, 1.1, 0), Vector3(1.6, 2.2, 1.0), _hall_doors[0])


func _refresh_portal_targets() -> void:
	for i in 4:
		if i < portal_count():
			set_portal_target(i, _rooms[_perm[i]]["entry"])


func _shuffle_rooms() -> void:
	if _rooms.is_empty():
		return
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	var fresh: Array[int] = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := rng2.randi_range(0, i)
		var tmp: int = fresh[i]
		fresh[i] = fresh[j]
		fresh[j] = tmp
	_perm = fresh
	_refresh_portal_targets()
	Audio.play_sfx("house_react", Vector3(0, 2, 0), -4.0)
	mission_notify("The house has rearranged its rooms.")
	if mission != null:
		mission.trigger_event("rooms_shuffled", {})


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.32, Color(0.5, 0.6, 0.9), Vector3(-0.9, 0.6, 0.2))
	add_light(Vector3(0, H - 0.3, 0), Color(1.0, 0.85, 0.62), 2.2, 11.0, true)
	add_light(Vector3(0, H - 0.3, -4.5), Color(0.9, 0.92, 1.0), 1.0, 6.0)
	add_light(Vector3(0, H - 0.3, 4.5), Color(1.0, 0.86, 0.7), 0.9, 6.0)
	var porch := add_light(Vector3(0, 2.5, 7.8), Color(1.0, 0.82, 0.55), 1.5, 9.0, true)
	register_flicker_light(porch)


func _build_furniture() -> void:
	# contract items live in the four rooms
	var r0: Vector3 = _rooms[0]["center"]
	var r1: Vector3 = _rooms[1]["center"]
	var r2: Vector3 = _rooms[2]["center"]
	var r3: Vector3 = _rooms[3]["center"]

	add_required(["bookshelf"], r0 + Vector3(-3.4, 0.03, -2.6), PI * 0.5, "library")
	add_decor("desk", r0 + Vector3(0.4, 0.03, -2.2), 0.0, "library")
	add_decor("books_stack", r0 + Vector3(0.4, 0.78, -2.2), 0.3, "library")
	add_optional(["mirror_tall"], r0 + Vector3(3.4, 0.03, 0.4), -PI * 0.5, "library", 0.7)
	add_decor("floor_lamp", r0 + Vector3(-3.5, 0.03, 2.4), 0.0, "library")

	add_required(["sofa_three", "sofa_two"], r1 + Vector3(-2.6, 0.03, 1.4), PI * 0.5, "studio")
	add_decor("armchair", r1 + Vector3(1.6, 0.03, 1.8), PI, "studio")
	add_optional(["gramophone"], r1 + Vector3(3.2, 0.03, -1.6), 0.0, "studio", 0.7)
	add_decor("painting_framed", r1 + Vector3(0.0, 0.03, -3.4), 0.0, "studio")

	add_required(["wardrobe"], r2 + Vector3(-3.3, 0.03, -1.6), PI * 0.5, "nursery")
	add_decor("bed_frame", r2 + Vector3(1.2, 0.03, 0.4), 0.0, "nursery")
	add_decor("mattress", r2 + Vector3(1.2, 0.6, 0.4), 0.0, "nursery")
	add_decor("toy_bear", r2 + Vector3(-1.8, 0.03, 2.6), 0.6, "nursery")
	add_required(["nightstand"], r2 + Vector3(3.0, 0.03, -2.8), 0.0, "nursery")

	add_required(["piano_upright", "organ"], r3 + Vector3(0.0, 0.03, -3.0), 0.0, "parlour")
	add_required(["dining_table"], r3 + Vector3(0.0, 0.03, 0.6), 0.0, "parlour")
	add_required(["dining_chair"], r3 + Vector3(-1.4, 0.03, 1.6), 0.0, "parlour")
	add_required(["dining_chair"], r3 + Vector3(1.4, 0.03, 1.6), 0.0, "parlour")
	add_optional(["sideboard"], r3 + Vector3(3.3, 0.03, -0.6), -PI * 0.5, "parlour", 0.6)

	# hall
	add_required(["tv"], Vector3(5.6, 0.55, -4.0), -PI * 0.5, "hall")
	add_decor("tv_stand", Vector3(5.6, 0.03, -4.0), -PI * 0.5, "hall")
	add_decor("bench", Vector3(-5.4, 0.03, 2.0), PI * 0.5, "hall")
	add_decor("plant", Vector3(-5.6, 0.03, 5.4), 0.0, "hall")
	add_required(["refrigerator"], Vector3(5.6, 0.03, 1.6), PI * 0.5, "hall")
	add_decor("crate", Vector3(-5.4, 0.03, -3.4), 0.4, "hall")
	add_decor("grandfather_clock", Vector3(-6.2, 0.03, -5.4), PI * 0.5, "hall")


func on_mission_start(_m: MissionManager) -> void:
	Audio.play_ambience("endless_hum", 2.5)
	Audio.play_music("prop_uneasy", 3.0)
	_refresh_portal_targets()


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host() or m.state != MissionManager.MState.ACTIVE:
		return
	_shuffle_timer -= delta
	if _shuffle_timer <= 0.0:
		_shuffle_timer = 70.0
		_shuffle_rooms()


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shuffle_rooms":
			_shuffle_rooms()
		"whisper_event":
			Audio.play_sfx("whisper", Vector3(rng.randf_range(-5, 5), 1.5, rng.randf_range(-5, 5)), -10.0)
			shuffle_small_objects(m)
		_:
			super(m, event_name, data)


func on_loud_noise(_m: MissionManager, _pos: Vector3) -> void:
	if rng.randf() < 0.4:
		_shuffle_rooms()
