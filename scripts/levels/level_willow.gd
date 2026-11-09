extends PropertyBase
## PROPERTY 01 - THE WILLOW RESIDENCE
##
## The teaching property. A normal suburban house with an abnormal amount of doorframe
## in the way. Layout is designed around the sofa: it fits the hallway, it does not fit
## the door, so the crew has to learn to rotate the load. Every required item has a
## deliberately validated route to the truck.

const H := 2.72
const T := 0.2

var _shuffle_timer := 25.0
var _porch_light: OmniLight3D
var _garage_light: OmniLight3D


func build() -> void:
	wall_color = Color("#9a8f7d")
	floor_color = Color("#7a6349")
	ceiling_color = Color("#d8d2c6")

	LevelKit.ground_plane(self, 90.0, Color("#2c3327"), 0.0)
	_build_exterior()
	_build_interior()
	_build_doors()
	_build_lighting()
	_build_furniture()
	_build_mission_props()

	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 11.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 6.6)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 0.1, 7.2)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.2, 0.1, 7.2)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 8.4)),
	]
	event_pool = ["light_flicker", "radio_on", "shuffle_small", "door_close", "light_flicker"]


func _build_exterior() -> void:
	var wall_c := Color("#8a8375")
	# house shell
	add_floor(Rect2(-6, -5, 12, 10))
	add_ceiling(Rect2(-6, -5, 12, 10), H)
	add_floor(Rect2(6, 0, 5, 5))     # garage floor
	add_ceiling(Rect2(6, 0, 5, 5), H)
	# south wall with front door
	add_wall(Vector3(-6, 0, 5), Vector3(6, 0, 5), H, T, [{"center": 6.0, "width": 1.15, "height": 2.1}], wall_c)
	# north wall
	add_wall(Vector3(-6, 0, -5), Vector3(6, 0, -5), H, T, [], wall_c)
	# west wall
	add_wall(Vector3(-6, 0, -5), Vector3(-6, 0, 5), H, T, [], wall_c)
	# east wall with the (sealed) garage access door
	add_wall(Vector3(6, 0, -5), Vector3(6, 0, 5), H, T, [{"center": 8.5, "width": 1.0, "height": 2.1}], wall_c)
	# garage outer walls
	add_wall(Vector3(6, 0, 5), Vector3(11, 0, 5), H, T, [], wall_c)
	add_wall(Vector3(11, 0, 0), Vector3(11, 0, 5), H, T, [], wall_c)
	add_wall(Vector3(6, 0, 0), Vector3(11, 0, 0), H, T, [], wall_c)

	# porch slab + step
	geo.box(Vector3(3.6, 0.08, 2.0), Vector3(0, 0.04, 6.0), Color("#6e6a60"))
	geo.box(Vector3(3.6, 0.04, 0.5), Vector3(0, 0.02, 7.15), Color("#67635a"))

	# garage door panel (does not open -- see contract notes)
	var g := MeshBuilder.new()
	for i in 7:
		g.box(Vector3(2.9, 0.28, 0.1), Vector3(8.5, 0.35 + i * 0.31, 5.06), Color("#b0aca0"), MeshBuilder.Mat.METAL, false)
	g.box(Vector3(3.1, 0.3, 0.12), Vector3(8.5, 2.45, 5.06), Color("#8a8778"), MeshBuilder.Mat.PLAIN, false)
	g.commit_static(self, "GarageDoor", false)

	# windows (glass + light spill)
	LevelKit.window_pane(self, Vector3(-4.0, 1.65, 4.96), 1.7, 1.25, 0.0, true)
	LevelKit.window_pane(self, Vector3(4.0, 1.65, 4.96), 1.5, 1.2, 0.0, true)
	LevelKit.window_pane(self, Vector3(-4.0, 1.65, -4.96), 1.4, 1.15, 0.0)
	LevelKit.window_pane(self, Vector3(4.0, 1.65, -4.96), 1.4, 1.15, 0.0)
	LevelKit.window_pane(self, Vector3(-5.96, 1.6, 2.5), 1.5, 1.2, PI * 0.5)
	LevelKit.window_pane(self, Vector3(5.96, 1.6, -3.4), 1.2, 1.1, PI * 0.5)

	# driveway
	geo.box(Vector3(6.5, 0.04, 12.0), Vector3(0, 0.02, 13.0), Color("#57544e"))
	# fence bits for framing
	for i in 12:
		geo.box(Vector3(0.12, 1.4, 0.12), Vector3(-9.0 + i * 1.6, 0.7, 16.0), Color("#6b5a44"))
	geo.box(Vector3(19.0, 0.12, 0.1), Vector3(0.0, 1.25, 16.0), Color("#6b5a44"))

	# a tree or two
	_tree(Vector3(-11.0, 0, 12.0), 3.4)
	_tree(Vector3(9.5, 0, 15.0), 2.8)


func _tree(pos: Vector3, h: float) -> void:
	var b := MeshBuilder.new()
	b.cyl(0.22, 0.32, h, Vector3(0, h * 0.5, 0), Color("#4a3a2a"), MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 8)
	b.sphere(h * 0.36, Vector3(0, h * 0.95, 0), Color("#2f3d2a"), MeshBuilder.Mat.PLAIN, false, h * 0.6)
	b.sphere(h * 0.28, Vector3(h * 0.2, h * 1.15, 0.15), Color("#35452f"), MeshBuilder.Mat.PLAIN, false, h * 0.5)
	var node := b.commit_static(self, "Tree", false)
	node.position = pos


func _build_interior() -> void:
	var ic := Color("#8e8577")
	# living / hallway
	add_wall(Vector3(-1.5, 0, 0), Vector3(-1.5, 0, 5), H, T, [{"center": 2.6, "width": 0.95, "height": 2.1}], ic)
	# hallway / kitchen
	add_wall(Vector3(1.5, 0, 0), Vector3(1.5, 0, 5), H, T, [{"center": 3.4, "width": 0.95, "height": 2.1}], ic)
	# south row / north row divider with archway
	add_wall(Vector3(-6, 0, 0), Vector3(6, 0, 0), H, T, [
		{"center": 6.0, "width": 1.3, "height": 2.2},
	], ic)
	# corridor / bedroom 1
	add_wall(Vector3(-1.5, 0, -5), Vector3(-1.5, 0, 0), H, T, [{"center": 2.5, "width": 0.95, "height": 2.1}], ic)
	# corridor / bedroom 2
	add_wall(Vector3(1.5, 0, -5), Vector3(1.5, 0, -2), H, T, [{"center": 1.5, "width": 0.95, "height": 2.1}], ic)
	# corridor / bathroom block
	add_wall(Vector3(1.5, 0, -2), Vector3(1.5, 0, 0), H, T, [], ic)
	# bedroom 2 / bathroom + laundry
	add_wall(Vector3(1.5, 0, -2), Vector3(6, 0, -2), H, T, [
		{"center": 1.5, "width": 0.8, "height": 2.1},
		{"center": 3.8, "width": 0.72, "height": 2.1},
	], ic)
	# laundry divider
	add_wall(Vector3(4.5, 0, -2), Vector3(4.5, 0, 0), H, T, [], ic)
	# kitchen / dining header beam (open plan)
	geo.box(Vector3(4.5, 0.45, 0.25), Vector3(3.75, H - 0.22, 2.0), ic)

	# floors are visually distinct per room
	geo.box(Vector3(4.5, 0.02, 5.0), Vector3(-3.75, 0.01, 2.5), Color("#6d5540"))    # living rug/floor
	geo.box(Vector3(3.0, 0.02, 5.0), Vector3(0, 0.01, 2.5), Color("#5c4a38"))        # hall
	geo.box(Vector3(4.5, 0.02, 5.0), Vector3(3.75, 0.01, 2.5), Color("#8a8a80"))     # kitchen tile
	geo.box(Vector3(4.5, 0.02, 2.0), Vector3(3.75, 0.01, 1.0), Color("#6d5540"))     # dining
	geo.box(Vector3(4.5, 0.02, 5.0), Vector3(-3.75, 0.01, -2.5), Color("#5f4c3a"))   # bedroom 1
	geo.box(Vector3(3.0, 0.02, 5.0), Vector3(0, 0.01, -2.5), Color("#544433"))       # corridor
	geo.box(Vector3(4.5, 0.02, 3.0), Vector3(3.75, 0.01, -3.5), Color("#5f4c3a"))    # bedroom 2
	geo.box(Vector3(3.0, 0.02, 2.0), Vector3(3.0, 0.01, -1.0), Color("#9aa0a0"))     # bathroom
	geo.box(Vector3(1.5, 0.02, 2.0), Vector3(5.25, 0.01, -1.0), Color("#8a8a80"))    # laundry
	geo.box(Vector3(5.0, 0.02, 5.0), Vector3(8.5, 0.01, 2.5), Color("#4a4a46"))      # garage


func _build_doors() -> void:
	add_door(Vector3(-0.575, 0, 5), 0.0, 1.15, 2.1, "Front Door", false, Color("#6b4a33"))
	add_door(Vector3(-1.5, 0, 2.12), -PI * 0.5, 0.95, 2.1, "Living Room Door", false, Color("#7d6448"))
	add_door(Vector3(1.5, 0, 2.92), -PI * 0.5, 0.95, 2.1, "Kitchen Door", false, Color("#7d6448"))
	add_door(Vector3(-1.5, 0, -3.0), -PI * 0.5, 0.95, 2.1, "Bedroom Door", false, Color("#6d5740"))
	add_door(Vector3(1.5, 0, -4.0), -PI * 0.5, 0.95, 2.1, "Second Bedroom Door", false, Color("#6d5740"))
	add_door(Vector3(2.6, 0, -2.0), 0.0, 0.8, 2.1, "Bathroom Door", false, Color("#8a8a86"))
	add_door(Vector3(4.94, 0, -2.0), 0.0, 0.72, 2.1, "Laundry Door", false, Color("#8a8a86"))
	add_door(Vector3(6.0, 0, 1.5), -PI * 0.5, 1.0, 2.1, "Garage Door", true, Color("#5a4a38"))


func _build_lighting() -> void:
	_build_outdoor_lights()
	var l1 := add_light(Vector3(-3.4, 2.52, 3.2), Color(1.0, 0.84, 0.62), 2.0, 8.0, true)
	register_flicker_light(l1)
	add_light(Vector3(-4.6, 1.35, 0.9), Color(1.0, 0.78, 0.55), 0.7, 4.0)
	add_light(Vector3(3.75, 2.52, 3.4), Color(1.0, 0.9, 0.72), 1.9, 7.0, true)
	add_light(Vector3(3.75, 2.52, 0.9), Color(1.0, 0.86, 0.66), 1.2, 5.5)
	add_light(Vector3(0, 2.55, 2.6), Color(1.0, 0.88, 0.7), 1.0, 5.0)
	LevelKit.corridor_strip(self, Vector3(0, 2.6, -1.4), 0.6, 0.0, Color(0.85, 0.9, 1.0), 0.55)
	LevelKit.corridor_strip(self, Vector3(0, 2.6, -4.0), 0.6, 0.0, Color(0.85, 0.9, 1.0), 0.5)
	add_light(Vector3(-3.8, 2.52, -2.6), Color(1.0, 0.82, 0.6), 1.5, 6.5, true)
	add_light(Vector3(3.75, 2.52, -3.6), Color(1.0, 0.8, 0.6), 1.1, 5.5)
	add_light(Vector3(3.0, 2.5, -1.0), Color(0.8, 0.9, 1.0), 0.8, 4.0)
	_garage_light = add_light(Vector3(8.5, 2.5, 2.5), Color(0.9, 0.95, 1.0), 0.75, 6.0)
	register_flicker_light(_garage_light)


func _build_outdoor_lights() -> void:
	LevelKit.moonlight(self, 0.5, Color(0.55, 0.68, 1.0), Vector3(-0.9, 0.5, 0.0))
	_porch_light = add_light(Vector3(0.0, 2.5, 5.7), Color(1.0, 0.85, 0.6), 1.6, 9.0, true)
	# a distant street lamp so the yard is not pitch black
	add_light(Vector3(-9.5, 4.4, 14.0), Color(1.0, 0.82, 0.5), 2.2, 16.0, false)
	var b := MeshBuilder.new()
	b.cyl(0.08, 0.12, 4.4, Vector3(0, 2.2, 0), Color("#3a3a3e"), MeshBuilder.Mat.METAL, false, Vector3.ZERO, 8)
	b.box(Vector3(0.5, 0.14, 0.3), Vector3(0.2, 4.4, 0), Color(1.0, 0.9, 0.7), MeshBuilder.Mat.EMISSIVE, false)
	var lamp_post := b.commit_static(self, "StreetLamp", false)
	lamp_post.position = Vector3(-9.5, 0, 14.0)


func _build_furniture() -> void:
	# ---- LIVING ROOM (required: sofa, tv)
	add_required(["sofa_three", "sofa_two"], Vector3(-4.85, 0.03, 3.3), PI * 0.5, "living")
	add_decor("coffee_table", Vector3(-3.75, 0.03, 3.3), 0.0, "living")
	add_decor("armchair", Vector3(-3.6, 0.03, 1.3), PI, "living")
	add_required(["tv"], Vector3(-1.95, 0.55, 3.3), -PI * 0.5, "living")
	add_decor("tv_stand", Vector3(-1.95, 0.03, 3.3), -PI * 0.5, "living")
	add_decor("floor_lamp", Vector3(-5.35, 0.03, 0.8), 0.0, "living")
	add_decor("bookshelf_small", Vector3(-5.5, 0.03, 2.0), PI * 0.5, "living")
	add_optional(["gramophone"], Vector3(-2.3, 0.03, 1.1), 0.0, "living", 0.7)
	add_decor("painting_framed", Vector3(-2.1, 0.03, 4.4), -PI * 0.35, "living")

	# ---- KITCHEN (required: refrigerator)
	add_required(["refrigerator"], Vector3(5.35, 0.03, 4.1), -PI * 0.5, "kitchen")
	add_decor("kitchen_counter", Vector3(2.7, 0.03, 4.6), 0.0, "kitchen")
	add_decor("sink_unit", Vector3(4.4, 0.03, 4.6), 0.0, "kitchen")
	add_decor("stove", Vector3(2.0, 0.03, 2.6), -PI * 0.5, "kitchen")
	add_decor("stool", Vector3(3.0, 0.03, 3.5), 0.0, "kitchen")
	add_decor("plant", Vector3(5.6, 0.03, 2.3), 0.0, "kitchen")

	# ---- DINING (required: table + 4 chairs)
	add_required(["dining_table"], Vector3(3.9, 0.03, 1.0), 0.0, "dining")
	add_required(["dining_chair", "stool"], Vector3(3.3, 0.03, 0.42), PI, "dining")
	add_required(["dining_chair", "stool"], Vector3(4.5, 0.03, 0.42), PI, "dining")
	add_required(["dining_chair", "stool"], Vector3(3.3, 0.03, 1.62), 0.0, "dining")
	add_required(["dining_chair", "stool"], Vector3(4.5, 0.03, 1.62), 0.0, "dining")
	add_decor("vase_ceramic", Vector3(3.9, 0.82, 1.0), 0.0, "dining")
	add_optional(["sideboard"], Vector3(5.5, 0.03, 0.6), -PI * 0.5, "dining", 0.65)

	# ---- HALL
	add_decor("bench", Vector3(-1.1, 0.03, 0.8), PI * 0.5, "hall")
	add_decor("plant", Vector3(1.1, 0.03, 4.5), 0.0, "hall")
	add_optional(["suitcase"], Vector3(1.0, 0.03, 1.4), 0.3, "hall", 0.6)

	# ---- CORRIDOR
	add_decor("plant", Vector3(1.15, 0.03, -0.7), 0.0, "corridor")

	# ---- BEDROOM 1 (required: wardrobe + 2 bedside cabinets)
	add_required(["wardrobe", "wardrobe_antique"], Vector3(-5.5, 0.03, -1.2), PI * 0.5, "bedroom1")
	add_required(["nightstand"], Vector3(-5.5, 0.03, -3.9), 0.0, "bedroom1")
	add_required(["nightstand"], Vector3(-3.0, 0.03, -3.9), 0.0, "bedroom1")
	add_decor("bed_frame", Vector3(-4.25, 0.03, -3.4), 0.0, "bedroom1")
	add_decor("table_lamp", Vector3(-5.5, 0.62, -3.9), 0.0, "bedroom1")
	add_optional(["mirror_tall"], Vector3(-2.2, 0.03, -1.1), PI * 0.5, "bedroom1", 0.7)
	add_decor("books_stack", Vector3(-3.0, 0.62, -3.9), 0.4, "bedroom1")

	# ---- BEDROOM 2
	add_decor("bed_frame", Vector3(4.4, 0.03, -4.0), 0.0, "bedroom2")
	add_decor("mattress", Vector3(4.4, 0.6, -4.0), 0.0, "bedroom2")
	add_optional(["dresser"], Vector3(5.5, 0.03, -2.8), -PI * 0.5, "bedroom2", 0.7)
	add_decor("toy_bear", Vector3(2.4, 0.03, -3.6), 0.5, "bedroom2")

	# ---- BATHROOM / LAUNDRY
	add_decor("toilet", Vector3(2.2, 0.03, -1.3), 0.0, "bathroom")
	add_decor("bathtub", Vector3(3.7, 0.03, -1.1), PI * 0.5, "bathroom")
	add_optional(["washing_machine"], Vector3(5.25, 0.03, -1.3), 0.0, "laundry", 0.75)

	# ---- GARAGE
	add_decor("crate", Vector3(7.6, 0.03, 2.0), 0.3, "garage")
	add_decor("crate", Vector3(8.3, 0.03, 2.5), -0.2, "garage")
	add_decor("freezer_chest", Vector3(9.9, 0.03, 4.0), PI * 0.5, "garage")
	add_decor("bookshelf_small", Vector3(10.3, 0.03, 2.0), -PI * 0.5, "garage")
	add_optional(["radio"], Vector3(7.6, 0.62, 2.0), 0.2, "garage", 0.5)


func _build_mission_props() -> void:
	var depart := Interactable.new()
	depart.name = "DepartPoint"
	depart.setup("Clock Out  •  End Contract", "[E] depart with the crew", Vector3(0, 0.9, 14.4), Vector3(0.9, 0.9, 0.9))
	depart.activated.connect(func(_p): if mission: mission.request_departure())
	add_child(depart)

	var board := Interactable.new()
	board.name = "ContractBoard"
	board.setup("Contract Board", "[E] re-read the contract", Vector3(1.2, 1.2, 5.6), Vector3(0.6, 0.8, 0.2))
	board.activated.connect(func(_p): Game.ui.open_contract())
	add_child(board)

	var b := MeshBuilder.new()
	b.box(Vector3(0.9, 0.7, 0.06), Vector3(1.2, 1.2, 5.62), Color("#e8e2d2"))
	b.box(Vector3(1.0, 0.8, 0.04), Vector3(1.2, 1.2, 5.66), Color("#6b4a33"))
	b.commit_static(self, "BoardVisual", false)


func on_mission_start(_m: MissionManager) -> void:
	Audio.play_ambience("suburb_night", 2.5)
	Audio.play_music("prop_calm", 3.0)
	if _porch_light:
		_porch_light.light_energy = 1.8


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host() or m.state != MissionManager.MState.ACTIVE:
		return
	_shuffle_timer -= delta
	if _shuffle_timer <= 0.0:
		_shuffle_timer = 45.0
		var moved := shuffle_small_objects(m)
		if moved > 0:
			Audio.play_sfx("house_creak", Vector3(0, 2, 0), -14.0)


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"shuffle_small":
			shuffle_small_objects(m)
			Audio.play_sfx("whisper", Vector3(rng.randf_range(-4, 4), 1.5, rng.randf_range(-4, 4)), -16.0)
		"picture_move":
			for f in m.furniture:
				if is_instance_valid(f) and str(f.item_id).begins_with("painting") and not f.is_held():
					f.global_position += Vector3(0, 0.4, 0)
					break
		_:
			super(m, event_name, data)


func on_loud_noise(m: MissionManager, pos: Vector3) -> void:
	# The Willow house is almost friendly: it just objects, loudly.
	Audio.play_sfx("house_creak", pos, -8.0)
	for d in doors:
		if d.global_position.distance_to(pos) < 7.0 and d.is_open and rng.randf() < 0.4:
			d.slam()
			break
