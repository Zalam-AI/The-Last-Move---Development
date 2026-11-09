extends PropertyBase
## PROPERTY 06 - THE GRAND MERIDIAN (ABANDONED HOTEL)
##
## Three floors, one elevator that lies about which floor it is on, and corridors that
## double back on themselves. The room numbers shuffle. The bell cart is not a ride.
## This is the long-haul transport property: everything has to come down to the lobby
## and out through a service entrance barely wider than the beds.

const FLOOR_H := 3.4
const T := 0.22
const W := 34.0
const D := 22.0

var _elevator: AnimatableBody3D
var _elevator_y := 0.0
var _elevator_target := 0.0
var _elevator_busy := false
var _number_labels: Array[Label3D] = []
var _number_timer := 55.0
var _portal_flip := 0.0


func build() -> void:
	wall_color = Color("#6d6255")
	floor_color = Color("#4a3f36")
	ceiling_color = Color("#8d8272")
	LevelKit.ground_plane(self, 130.0, Color("#1c2220"), 0.0)
	for floor in 3:
		_build_floor(floor)
	_build_elevator()
	_build_doors()
	_build_lighting()
	_build_room_numbers()
	_build_furniture()
	_build_portals()
	add_mission_props(Vector3(0, 0.9, 22.4), Vector3(-2.0, 1.2, 10.4))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 19.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 10.6)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 0.1, 11.4)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.2, 0.1, 11.4)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 12.6)),
	]
	event_pool = ["light_flicker", "door_close", "numbers_shuffle", "light_flicker", "elevator_stall"]


func _build_floor(floor: int) -> void:
	var y := floor * FLOOR_H
	var wc := wall_color.darkened(floor * 0.06)
	# footprint x -17..17, z -11..11
	LevelKit.floor_rect(geo, Rect2(-17, -11, 34, 22), y, floor_color)
	LevelKit.ceiling_rect(geo, Rect2(-17, -11, 34, 22), y + FLOOR_H, ceiling_color)
	if floor == 2:
		add_wall(Vector3(-17, y + FLOOR_H, -11), Vector3(17, y + FLOOR_H, -11), 0.2, 1.0, [], ceiling_color)
	LevelKit.wall(geo, Vector3(-17, y, 11), Vector3(17, y, 11), FLOOR_H, T, wc,
		[{"center": 34.0, "width": 3.4, "height": 2.8}] if floor == 0 else [])
	LevelKit.wall(geo, Vector3(-17, y, -11), Vector3(17, y, -11), FLOOR_H, T, wc, [])
	LevelKit.wall(geo, Vector3(-17, y, -11), Vector3(-17, y, 11), FLOOR_H, T, wc, [])
	LevelKit.wall(geo, Vector3(17, y, -11), Vector3(17, y, 11), FLOOR_H, T, wc, [])
	# central corridor running east-west, guest rooms north and south
	LevelKit.wall(geo, Vector3(-17, y, -3.2), Vector3(17, y, -3.2), FLOOR_H, T, wc,
		_room_door_openings(floor, true))
	LevelKit.wall(geo, Vector3(-17, y, 3.2), Vector3(17, y, 3.2), FLOOR_H, T, wc,
		_room_door_openings(floor, false))
	# room dividers north side
	for x in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		LevelKit.wall(geo, Vector3(x, y, -11), Vector3(x, y, -3.2), FLOOR_H, T, wc, [])
		LevelKit.wall(geo, Vector3(x + 2.6, y, 3.2), Vector3(x + 2.6, y, 11), FLOOR_H, T, wc, [])
	# corridor carpet
	geo.box(Vector3(34.0, 0.02, 6.4), Vector3(0, y + 0.012, 0), Color("#5a3a34"))
	if floor == 0:
		geo.box(Vector3(20.0, 0.03, 12.0), Vector3(0, 0.015, 6.0), Color("#6b5a44"))


func _room_door_openings(floor: int, north: bool) -> Array:
	var openings: Array = []
	for x in [-8.25, -2.75, 2.75, 8.25]:
		openings.append({"center": x + 17.0, "width": 1.1, "height": 2.2})
	return openings


func _build_elevator() -> void:
	var shaft_x := -14.5
	var shaft_z := -7.5
	# shaft walls
	for floor in 3:
		var y := floor * FLOOR_H
		geo.box(Vector3(0.2, FLOOR_H, 3.4), Vector3(shaft_x + 1.7, y + FLOOR_H * 0.5, shaft_z), Color("#3f3a34"))
		geo.box(Vector3(3.6, FLOOR_H, 0.2), Vector3(shaft_x, y + FLOOR_H * 0.5, shaft_z - 1.7), Color("#3f3a34"))
	_elevator = AnimatableBody3D.new()
	_elevator.name = "Elevator"
	_elevator.sync_to_physics = false
	_elevator.position = Vector3(shaft_x, 0.0, shaft_z)
	var eb := MeshBuilder.new()
	eb.box(Vector3(3.2, 0.2, 3.2), Vector3(0, 0.1, 0), Color("#4a4a44"), MeshBuilder.Mat.METAL, true)
	eb.box(Vector3(3.2, 1.1, 0.1), Vector3(0, 0.65, -1.55), Color("#5a5a52"), MeshBuilder.Mat.METAL, true)
	eb.box(Vector3(0.1, 1.1, 3.2), Vector3(-1.55, 0.65, 0), Color("#5a5a52"), MeshBuilder.Mat.METAL, true)
	eb.box(Vector3(3.2, 2.4, 0.08), Vector3(0, 1.3, 1.55), Color("#6a6a60", 0.5), MeshBuilder.Mat.GLASS, false)
	eb.commit_static(_elevator, "Car", false)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 0.3, 3.2)
	cs.shape = box
	cs.position = Vector3(0, 0.15, 0)
	_elevator.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = eb.build_mesh()
	_elevator.add_child(mi)
	add_child(_elevator)
	# call buttons at each floor
	for floor in 3:
		var btn := Interactable.new()
		btn.name = "ElevatorCall%d" % floor
		btn.setup("Elevator Call  •  Floor %d" % (floor + 1), "[E] call the elevator", Vector3(shaft_x + 2.1, floor * FLOOR_H + 1.2, shaft_z), Vector3(0.4, 0.4, 0.4))
		btn.activated.connect(_on_elevator_call.bind(floor))
		add_child(btn)
		var l := Label3D.new()
		l.text = "ELEVATOR\nCALL"
		l.font_size = 32
		l.pixel_size = 0.004
		l.modulate = Color("#e8b13a")
		l.position = Vector3(shaft_x + 2.1, floor * FLOOR_H + 1.75, shaft_z)
		add_child(l)


func _on_elevator_call(_p: Node, floor: int) -> void:
	if _elevator_busy:
		Game.ui.notify("The elevator is already deciding where it wants to go.", "warning")
		return
	# it only sometimes goes where you asked
	var target_floor := floor
	if rng.randf() < 0.35:
		target_floor = rng.randi_range(0, 2)
		Game.ui.notify("The elevator has opinions about floors.", "spooky")
	_move_elevator_to(float(target_floor) * FLOOR_H, target_floor)


func _move_elevator_to(target_y: float, floor: int) -> void:
	_elevator_busy = true
	_elevator_target = target_y
	Audio.play_sfx("elevator", _elevator.global_position, -4.0)
	var tw := create_tween()
	tw.tween_property(_elevator, "position:y", target_y, 2.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		_elevator_busy = false
		Audio.play_sfx("door_open", _elevator.global_position, -8.0))


func _build_doors() -> void:
	add_door(Vector3(-1.7, 0, 11), 0.0, 3.4, 2.8, "Main Entrance", false, Color("#3a2c22"))
	# guest room doors (a representative set: too many doors is worse than too few)
	for floor in 3:
		var y := floor * FLOOR_H
		for i in 4:
			var x := -8.25 + i * 5.5
			add_door(Vector3(x - 0.55, y, -3.2), 0.0, 1.1, 2.2, "Room %d%02d" % [floor + 1, i + 1], false, Color("#5a4432"))
		for i in 4:
			var x2 := -8.25 + i * 5.5
			add_door(Vector3(x2 - 0.55, y, 3.2), 0.0, 1.1, 2.2, "Room %d%02d" % [floor + 1, i + 6], false, Color("#5a4432"))


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.28, Color(0.5, 0.6, 0.95), Vector3(-0.9, 0.55, 0.1))
	for floor in 3:
		var y := floor * FLOOR_H
		for i in 4:
			var l := add_light(Vector3(-12.0 + i * 8.0, y + FLOOR_H - 0.4, 0.0), Color(0.92, 0.95, 1.0), 1.1, 9.0, i % 2 == 0)
			register_flicker_light(l)
		add_light(Vector3(-14.5, y + FLOOR_H - 0.4, -7.5), Color(1.0, 0.9, 0.7), 0.9, 6.0)
		add_light(Vector3(12.0, y + FLOOR_H - 0.4, -7.0), Color(1.0, 0.88, 0.66), 0.7, 8.0)
		add_light(Vector3(12.0, y + FLOOR_H - 0.4, 7.0), Color(1.0, 0.88, 0.66), 0.7, 8.0)
	# lobby chandelier
	add_light(Vector3(0, 3.0, 6.0), Color(1.0, 0.85, 0.6), 2.6, 14.0, true)
	add_light(Vector3(0, 2.5, 12.5), Color(1.0, 0.9, 0.7), 1.6, 10.0, true)


func _build_room_numbers() -> void:
	for floor in 3:
		for i in 4:
			var l := Label3D.new()
			l.text = "%d%02d" % [floor + 1, i + 1]
			l.font_size = 40
			l.pixel_size = 0.004
			l.modulate = Color("#d8cba8")
			l.position = Vector3(-8.25 + i * 5.5, floor * FLOOR_H + 2.45, -3.05)
			add_child(l)
			_number_labels.append(l)


func _shuffle_numbers() -> void:
	var nums: Array[String] = []
	for floor in 3:
		for i in 4:
			nums.append("%d%02d" % [floor + 1, i + 1])
	for i in range(nums.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: String = nums[i]
		nums[i] = nums[j]
		nums[j] = t
	for idx in _number_labels.size():
		_number_labels[idx].text = nums[idx]
	mission_notify("The room numbers have changed. Some of them are now wrong.")


func _build_portals() -> void:
	# Two corridor mouths that loop: walk east, arrive at the west end of the same corridor.
	add_portal(Vector3(16.0, 1.1, 0.0), Vector3(1.2, 2.2, 5.0),
		Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-15.4, 0.1, 0.0)), "")
	add_portal(Vector3(-16.0, FLOOR_H + 1.1, 0.0), Vector3(1.2, 2.2, 5.0),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(15.4, FLOOR_H + 0.1, 0.0)), "")


func _build_furniture() -> void:
	# LOBBY (floor 0)
	add_decor("kitchen_counter", Vector3(-6.0, 0.03, 8.0), PI, "lobby")
	add_decor("bench", Vector3(3.0, 0.03, 8.6), 0.0, "lobby")
	add_decor("plant", Vector3(-9.0, 0.03, 9.4), 0.0, "lobby")
	add_decor("plant", Vector3(9.0, 0.03, 9.4), 0.0, "lobby")
	add_required(["piano_upright", "organ"], Vector3(12.0, 0.03, 8.0), PI, "lobby")
	add_required(["sofa_two"], Vector3(-12.0, 0.03, 8.0), PI * 0.5, "lobby")
	add_decor("cart", Vector3(0.0, 0.03, 4.6), 0.5, "lobby")
	add_decor("grandfather_clock", Vector3(-16.4, 0.03, 6.0), PI * 0.5, "lobby")

	# FLOOR 1 guest rooms
	add_required(["bed_frame"], Vector3(-13.0, FLOOR_H + 0.03, -8.0), 0.0, "room101")
	add_required(["dresser"], Vector3(-16.0, FLOOR_H + 0.03, -5.0), PI * 0.5, "room101")
	add_required(["tv"], Vector3(-11.0, FLOOR_H + 0.03, -10.2), 0.6, "room101")
	add_decor("tv_stand", Vector3(-13.2, FLOOR_H + 0.03, -10.0), 0.0, "room101")
	add_required(["wardrobe"], Vector3(-8.0, FLOOR_H + 0.03, -9.4), 0.0, "room102")
	add_decor("hotel_armchair", Vector3(-6.0, FLOOR_H + 0.03, -6.0), 0.0, "room102")
	add_required(["dining_table"], Vector3(6.0, FLOOR_H + 0.03, -8.0), 0.0, "room103")
	add_required(["sofa_three"], Vector3(12.6, FLOOR_H + 0.03, 8.0), -PI * 0.5, "room106")

	# FLOOR 2
	add_required(["piano_grand"], Vector3(-12.0, FLOOR_H * 2 + 0.03, -7.0), 0.0, "suite201")
	add_required(["nightstand"], Vector3(-8.6, FLOOR_H * 2 + 0.03, -9.6), 0.0, "suite201")
	add_decor("bed_frame", Vector3(-13.0, FLOOR_H * 2 + 0.03, -9.0), 0.0, "suite201")
	add_decor("mattress", Vector3(-13.0, FLOOR_H * 2 + 0.6, -9.0), 0.0, "suite201")
	add_required(["wardrobe_antique"], Vector3(-4.0, FLOOR_H * 2 + 0.03, -9.0), 0.0, "suite202")
	add_decor("hotel_armchair", Vector3(2.0, FLOOR_H * 2 + 0.03, 6.0), PI, "room206")
	add_required(["sideboard"], Vector3(8.0, FLOOR_H * 2 + 0.03, 8.6), PI, "room207")
	add_optional(["mirror_tall"], Vector3(14.0, FLOOR_H * 2 + 0.03, 6.0), -PI * 0.5, "room208", 0.8)
	add_optional(["gramophone"], Vector3(-1.0, FLOOR_H * 2 + 0.03, -9.4), 0.0, "suite202", 0.7)
	add_decor("bookshelf_small", Vector3(15.6, FLOOR_H + 0.03, -8.0), -PI * 0.5, "room104")
	add_decor("washing_machine", Vector3(-15.0, FLOOR_H + 0.03, 8.6), 0.0, "service")


func on_mission_start(_m: MissionManager) -> void:
	Audio.play_ambience("hotel_hum", 2.5)
	Audio.play_music("prop_tension", 3.0)
	Audio.play_voice("training_01", "PA: This is a reminder that the Grand Meridian has been closed since 1974. Please enjoy your stay.", -4.0)


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host() or m.state != MissionManager.MState.ACTIVE:
		return
	_number_timer -= delta
	if _number_timer <= 0.0:
		_number_timer = 75.0
		_shuffle_numbers()
	_portal_flip -= delta
	if _portal_flip <= 0.0:
		_portal_flip = 45.0
		# swap which corridor mouth dumps you where
		add_portal(Vector3(16.0, FLOOR_H * 2 + 1.1, 0.0), Vector3(1.2, 2.2, 5.0),
			Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 4.0)), "")


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"numbers_shuffle":
			_shuffle_numbers()
		"elevator_stall":
			Audio.play_sfx("elevator", _elevator.global_position, -2.0)
			_elevator_busy = false
			mission_notify("The elevator has stopped between floors. It does that.")
			_elevator.position.y = _elevator.position.y + 0.4
		_:
			super(m, event_name, data)


func on_loud_noise(_m: MissionManager, pos: Vector3) -> void:
	Audio.play_sfx("hotel_knock", pos, -6.0)
	mission_notify("Someone has knocked on a door. The hotel is empty.")
