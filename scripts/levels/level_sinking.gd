extends PropertyBase
## PROPERTY 04 - THE SINKING HOUSE
##
## Harbour Row. The water is not tidal and it is not stopping. Buoyancy, drag and the
## electrical hazard below the kitchen all come from the rising level, so the crew has to
## decide what is worth going back down for. Heavy items sink, light ones drift, and the
## basement becomes a swimming pool with furniture in it.

const H := 2.9
const T := 0.2
const BASEMENT_Y := -2.9
const WATER_START := -2.7
const WATER_END := 1.45

var _water: MeshInstance3D
var _water_mat: StandardMaterial3D
var water_level := WATER_START
var _arc_timer := 0.0
var _hazard_timer := 0.0


func build() -> void:
	wall_color = Color("#5f6663")
	floor_color = Color("#4a4238")
	ceiling_color = Color("#8a8f88")
	LevelKit.ground_plane(self, 110.0, Color("#20282c"), 0.0)
	_build_ground_floor()
	_build_basement()
	_build_doors()
	_build_lighting()
	_build_water()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 15.4), Vector3(1.3, 1.2, 8.3))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 12.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 8.4)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.0, 0.1, 9.0)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.0, 0.1, 9.0)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 10.2)),
	]
	event_pool = ["light_flicker", "door_close", "surge", "light_flicker", "surge"]


func _build_ground_floor() -> void:
	var wc := Color("#666d6a")
	add_floor(Rect2(-11, -9, 22, 17))
	add_ceiling(Rect2(-11, -9, 22, 17), H)
	add_wall(Vector3(-11, 0, 8), Vector3(11, 0, 8), H, T, [{"center": 11.0, "width": 1.3, "height": 2.35}], wc)
	add_wall(Vector3(-11, 0, -9), Vector3(11, 0, -9), H, T, [], wc)
	add_wall(Vector3(-11, 0, -9), Vector3(-11, 0, 8), H, T, [], wc)
	add_wall(Vector3(11, 0, -9), Vector3(11, 0, 8), H, T, [], wc)
	# living room / kitchen / hallway / bedroom partitions
	LevelKit.wall(geo, Vector3(-2, 0, 0), Vector3(-2, 0, 8), H, T, wc, [{"center": 3.0, "width": 1.3, "height": 2.2}])
	LevelKit.wall(geo, Vector3(2, 0, 0), Vector3(2, 0, 8), H, T, wc, [{"center": 3.0, "width": 1.3, "height": 2.2}])
	LevelKit.wall(geo, Vector3(-11, 0, 0), Vector3(11, 0, 0), H, T, wc,
		[{"center": 11.0, "width": 1.4, "height": 2.2}, {"center": 17.0, "width": 1.1, "height": 2.2}])
	LevelKit.wall(geo, Vector3(-2, 0, -9), Vector3(-2, 0, 0), H, T, wc, [{"center": 4.0, "width": 1.1, "height": 2.2}])
	LevelKit.wall(geo, Vector3(2, 0, -9), Vector3(2, 0, 0), H, T, wc, [{"center": 4.0, "width": 1.1, "height": 2.2}])
	# window frames looking out at grey water
	LevelKit.window_pane(self, Vector3(-7.0, 1.6, 8.0), 2.0, 1.3, 0.0)
	LevelKit.window_pane(self, Vector3(6.0, 1.6, 8.0), 1.6, 1.2, 0.0)
	# floors
	geo.box(Vector3(9.0, 0.02, 8.0), Vector3(-6.5, 0.012, 4.0), Color("#3f3a33"))
	geo.box(Vector3(9.0, 0.02, 8.0), Vector3(6.5, 0.012, 4.0), Color("#4e4a42"))
	geo.box(Vector3(4.0, 0.02, 17.0), Vector3(0, 0.012, -0.5), Color("#3a352e"))


func _build_basement() -> void:
	var wc := Color("#4e5451")
	# basement x -8..8, z -7..5 at y = BASEMENT_Y
	LevelKit.floor_rect(geo, Rect2(-8, -7, 16, 12), BASEMENT_Y, Color("#33302b"))
	LevelKit.ceiling_rect(geo, Rect2(-8, -7, 16, 12), BASEMENT_Y + 2.7, Color("#3a3733"))
	LevelKit.wall(geo, Vector3(-8, BASEMENT_Y, 5), Vector3(8, BASEMENT_Y, 5), 2.7, T, wc, [])
	LevelKit.wall(geo, Vector3(-8, BASEMENT_Y, -7), Vector3(8, BASEMENT_Y, -7), 2.7, T, wc, [])
	LevelKit.wall(geo, Vector3(-8, BASEMENT_Y, -7), Vector3(-8, BASEMENT_Y, 5), 2.7, T, wc, [])
	LevelKit.wall(geo, Vector3(8, BASEMENT_Y, -7), Vector3(8, BASEMENT_Y, 5), 2.7, T, wc, [])
	# stairwell cut in the ground floor over x 5..7.4, z -2..2
	LevelKit.stairs(geo, Vector3(6.2, BASEMENT_Y, -2.0), Vector3(6.2, 0.0, 2.4), 1.6, Color("#4a4a44"), 16)
	LevelKit.railing(geo, Vector3(5.3, BASEMENT_Y + 1.2, -2.0), Vector3(5.3, 1.2, 2.4), 0.95, Color("#3f3f38"))
	# support columns
	for i in 3:
		geo.box(Vector3(0.28, 2.7, 0.28), Vector3(-4.0 + i * 4.0, BASEMENT_Y + 1.35, -1.0), Color("#4a4740"))
	# pipes along the ceiling
	geo.box(Vector3(14.0, 0.16, 0.16), Vector3(0, BASEMENT_Y + 2.5, 4.4), Color("#6a5a4a"), MeshBuilder.Mat.METAL)
	geo.box(Vector3(0.16, 0.16, 10.0), Vector3(-7.4, BASEMENT_Y + 2.55, 0), Color("#6a5a4a"), MeshBuilder.Mat.METAL)


func _build_doors() -> void:
	add_door(Vector3(-0.7, 0, 8), 0.0, 1.3, 2.35, "Front Door", false, Color("#4a4f4a"))
	add_door(Vector3(-2, 0, 2.0), -PI * 0.5, 1.3, 2.2, "Living Room", false, Color("#5a5148"))
	add_door(Vector3(2, 0, 2.0), -PI * 0.5, 1.3, 2.2, "Kitchen", false, Color("#5a5148"))
	add_door(Vector3(-5.0, 0, 0), 0.0, 1.1, 2.2, "Bedroom", false, Color("#5a5148"))


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.46, Color(0.55, 0.68, 1.0), Vector3(-0.9, 0.5, 0.15))
	var l1 := add_light(Vector3(-6.5, H - 0.3, 4.0), Color(1.0, 0.84, 0.6), 1.9, 9.0, true)
	register_flicker_light(l1)
	add_light(Vector3(6.5, H - 0.3, 4.0), Color(0.95, 0.95, 0.85), 1.6, 8.0, true)
	add_light(Vector3(0, H - 0.3, 2.0), Color(0.9, 0.95, 1.0), 0.9, 6.0)
	add_light(Vector3(-6.0, H - 0.3, -4.0), Color(0.9, 0.9, 1.0), 0.8, 6.0)
	add_light(Vector3(6.0, H - 0.3, -4.0), Color(1.0, 0.9, 0.7), 0.8, 6.0)
	# basement: single dying bulb
	var b := add_light(Vector3(0, BASEMENT_Y + 2.4, 0), Color(0.9, 0.95, 1.0), 1.1, 9.0, true)
	register_flicker_light(b)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.09, 0.19, 0.23, 0.62)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.14
	_water_mat.metallic = 0.25
	_water_mat.rim_enabled = true
	_water_mat.rim = 0.4
	_water_mat.emission_enabled = true
	_water_mat.emission = Color(0.04, 0.1, 0.12)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	_water.material_override = _water_mat
	_water.position = Vector3(0, WATER_START, 0)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


func _build_furniture() -> void:
	# ground floor - living room
	add_required(["sofa_three", "sofa_two"], Vector3(-9.0, 0.03, 5.6), PI * 0.5, "living")
	add_required(["tv"], Vector3(-3.4, 0.55, 5.0), -PI * 0.5, "living")
	add_decor("tv_stand", Vector3(-3.4, 0.03, 5.0), -PI * 0.5, "living")
	add_decor("coffee_table", Vector3(-6.4, 0.03, 5.2), 0.0, "living")
	add_optional(["mirror_tall"], Vector3(-10.4, 0.03, 1.2), PI * 0.5, "living", 0.7)

	# kitchen
	add_required(["refrigerator"], Vector3(10.4, 0.03, 6.6), -PI * 0.5, "kitchen")
	add_decor("kitchen_counter", Vector3(5.0, 0.03, 7.6), 0.0, "kitchen")
	add_decor("stove", Vector3(7.6, 0.03, 7.6), PI, "kitchen")
	add_required(["dining_table"], Vector3(7.0, 0.03, 3.6), 0.0, "kitchen")
	add_required(["dining_chair"], Vector3(6.0, 0.03, 2.8), 0.3, "kitchen")
	add_required(["dining_chair"], Vector3(8.0, 0.03, 2.8), -0.3, "kitchen")

	# bedroom
	add_decor("bed_frame", Vector3(-7.0, 0.03, -6.4), 0.0, "bedroom")
	add_decor("mattress", Vector3(-7.0, 0.6, -6.4), 0.0, "bedroom")
	add_required(["wardrobe"], Vector3(-10.3, 0.03, -3.4), PI * 0.5, "bedroom")
	add_decor("nightstand", Vector3(-4.6, 0.03, -6.8), 0.0, "bedroom")

	# basement - the expensive stuff, down where the water is
	add_required(["piano_upright", "organ"], Vector3(-6.0, BASEMENT_Y + 0.03, 3.4), 0.0, "basement")
	add_required(["freezer_chest"], Vector3(6.8, BASEMENT_Y + 0.03, -5.6), -PI * 0.5, "basement")
	add_required(["sideboard"], Vector3(-7.2, BASEMENT_Y + 0.03, -5.6), PI * 0.5, "basement")
	add_decor("bookshelf", Vector3(0.0, BASEMENT_Y + 0.03, -6.6), 0.0, "basement")
	add_decor("crate", Vector3(1.6, BASEMENT_Y + 0.03, 1.6), 0.3, "basement")
	add_decor("crate", Vector3(3.0, BASEMENT_Y + 0.03, 3.0), -0.2, "basement")
	add_required(["bookshelf_small"], Vector3(7.4, BASEMENT_Y + 0.03, 1.0), -PI * 0.5, "basement")
	add_decor("washing_machine", Vector3(-3.0, BASEMENT_Y + 0.03, -6.4), 0.0, "basement")
	add_optional(["gramophone"], Vector3(4.0, BASEMENT_Y + 0.03, 3.6), 0.4, "basement", 0.8)


func on_mission_start(m: MissionManager) -> void:
	Audio.play_ambience("water_ambience", 2.5)
	Audio.play_music("prop_tension", 3.0)
	water_level = WATER_START
	m.water_height = water_level
	if _water:
		_water.position.y = water_level


func _water_from_time(m: MissionManager) -> float:
	var elapsed := m.time_total - m.time_left
	var t := clampf(elapsed / maxf(1.0, m.time_total), 0.0, 1.15)
	return lerpf(WATER_START, WATER_END, t)


func mission_tick(m: MissionManager, delta: float) -> void:
	water_level = _water_from_time(m)
	m.water_height = water_level
	if _water:
		_water.position.y = water_level
		_water_mat.albedo_color.a = 0.55 + 0.08 * sin(Time.get_ticks_msec() * 0.001)
	if not Net.is_host():
		return
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = 0.5
		for p in Game.players_root.get_children():
			if p is Player and p.global_position.y < water_level - 0.2:
				p.take_damage(1.2, "water")
	# buoyancy: light things float, heavy things stay where the house left them
	for f in m.furniture:
		if not is_instance_valid(f) or f.delivered:
			continue
		var submerged := water_level - f.global_position.y
		if submerged <= 0.05:
			continue
		var vol := f.size.x * f.size.y * f.size.z
		var displaced := clampf(submerged / maxf(0.05, f.size.y), 0.0, 1.0) * vol * 720.0
		var lift := displaced - f.mass
		if absf(lift) > 0.5:
			f.apply_central_force(Vector3.UP * lift * 9.0 * water_drag_factor(f))
			f.apply_central_force(-f.linear_velocity * f.mass * 0.8)
	# electrical hazard once the water reaches the sockets
	if water_level > 0.55:
		_hazard_timer -= delta
		if _hazard_timer <= 0.0:
			_hazard_timer = 1.0
			for p in Game.players_root.get_children():
				if not (p is Player):
					continue
				var pl := p as Player
				if pl.global_position.y < water_level - 0.1 and pl.global_position.y > -1.5:
					pl.take_damage(4.0, "electricity")
					Audio.play_sfx("light_buzz", pl.global_position, -6.0)
					m.trigger_event("shock", {"pos": pl.global_position})


func water_drag_factor(f: Furniture) -> float:
	return clampf(120.0 / maxf(20.0, f.mass), 0.25, 1.6)


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"surge":
			Audio.play_sfx("water_surge", data.get("pos", Vector3(0, 0, 0)), -3.0)
			mission_notify("The water found another way in.")
		"shock":
			Audio.play_sfx("light_buzz", data.get("pos", Vector3.ZERO), -2.0)
		_:
			super(m, event_name, data)


func on_loud_noise(m: MissionManager, pos: Vector3) -> void:
	Audio.play_sfx("water_surge", pos, -8.0)
	# noise in a flooded basement is a bad idea
	if water_level > 0.2:
		for d in doors:
			if d.is_open and rng.randf() < 0.5:
				d.slam()
				break
