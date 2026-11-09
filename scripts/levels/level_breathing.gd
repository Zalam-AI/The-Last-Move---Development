extends PropertyBase
## PROPERTY 07 - THE HOUSE THAT BREATHES
##
## The building is not made of walls. It is made of walls that move, floors that inhale,
## and passages that close when you make too much noise. Everything here is a moving
## collider, which means furniture carried through it behaves like furniture carried
## through a moving animal.

const H := 3.0
const T := 0.24

var _moving_walls: Array[AnimatableBody3D] = []
var _wall_data: Array[Dictionary] = []
var _floor_body: AnimatableBody3D
var _breath := 0.0
var _breath_rate := 0.22
var _agitation := 0.0
var _spasms: Array[AnimatableBody3D] = []
var _spasm_state: Array[bool] = []


func build() -> void:
	wall_color = Color("#5c3a3a")
	floor_color = Color("#4a2e2c")
	ceiling_color = Color("#6b4040")
	LevelKit.ground_plane(self, 110.0, Color("#1a1416"), 0.0)
	_build_shell()
	_build_breathing_floor()
	_build_moving_walls()
	_build_obstructions()
	_build_doors()
	_build_lighting()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 17.4), Vector3(1.3, 1.2, 9.4))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 14.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 9.4)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.2, 0.1, 10.2)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.2, 0.1, 10.2)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 11.4)),
	]
	event_pool = ["breath_spasm", "light_flicker", "passage_close", "breath_spasm", "door_close"]


func _build_shell() -> void:
	var wc := wall_color
	# footprint x -13..13, z -10..9
	add_floor(Rect2(-13, -10, 26, 19))
	add_ceiling(Rect2(-13, -10, 26, 19), H)
	add_wall(Vector3(-13, 0, 9), Vector3(13, 0, 9), H, T, [{"center": 13.0, "width": 1.4, "height": 2.4}], wc)
	add_wall(Vector3(-13, 0, -10), Vector3(13, 0, -10), H, T, [], wc)
	add_wall(Vector3(-13, 0, -10), Vector3(-13, 0, 9), H, T, [], wc)
	add_wall(Vector3(13, 0, -10), Vector3(13, 0, 9), H, T, [], wc)
	# organic partitions: ribbed, irregular
	LevelKit.wall(geo, Vector3(-4, 0, -1), Vector3(-4, 0, 9), H, T, wc, [{"center": 5.0, "width": 1.5, "height": 2.3}])
	LevelKit.wall(geo, Vector3(4, 0, -1), Vector3(4, 0, 9), H, T, wc, [{"center": 5.0, "width": 1.5, "height": 2.3}])
	LevelKit.wall(geo, Vector3(-13, 0, -1), Vector3(13, 0, -1), H, T, wc,
		[{"center": 13.0, "width": 1.6, "height": 2.4}, {"center": 5.0, "width": 1.2, "height": 2.2}])
	# ribs on the walls, so the architecture reads as anatomy
	for i in 14:
		var x := -12.0 + i * 1.8
		geo.box(Vector3(0.22, H * 0.9, 0.3), Vector3(x, H * 0.45, -9.7), Color("#6b4444"), MeshBuilder.Mat.PLAIN, false)
		geo.box(Vector3(0.22, H * 0.9, 0.3), Vector3(x, H * 0.45, 8.7), Color("#6b4444"), MeshBuilder.Mat.PLAIN, false)
	# veins / membrane patches on the floor
	for i in 8:
		geo.cyl(0.9, 1.2, 0.03, Vector3(rng.randf_range(-11, 11), 0.02, rng.randf_range(-9, 8)), Color("#5a3030"),
			MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 9)


func _build_breathing_floor() -> void:
	_floor_body = AnimatableBody3D.new()
	_floor_body.name = "BreathingFloor"
	_floor_body.sync_to_physics = false
	_floor_body.position = Vector3(0, 0, 0)
	var fb := MeshBuilder.new()
	fb.box(Vector3(7.4, 0.25, 9.5), Vector3(0, 0, 4.0), Color("#5e3634"))
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.4, 0.25, 9.5)
	cs.shape = box
	cs.position = Vector3(0, 0, 4.0)
	_floor_body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = fb.build_mesh()
	_floor_body.add_child(mi)
	add_child(_floor_body)


func _build_moving_walls() -> void:
	# three walls that slide, opening and closing routes through the house
	var specs := [
		{"pos": Vector3(-2.0, 0, 2.0), "size": Vector3(0.3, H, 2.2), "axis": Vector3(1, 0, 0), "amp": 2.0, "speed": 0.35},
		{"pos": Vector3(2.0, 0, 5.5), "size": Vector3(0.3, H, 2.2), "axis": Vector3(1, 0, 0), "amp": 2.2, "speed": 0.28},
		{"pos": Vector3(-9.0, 0, -1.0), "size": Vector3(3.0, H, 0.3), "axis": Vector3(0, 0, 1), "amp": 1.8, "speed": 0.22},
	]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var body := AnimatableBody3D.new()
		body.name = "MovingWall%d" % i
		body.sync_to_physics = false
		body.position = spec["pos"]
		var b := MeshBuilder.new()
		var s: Vector3 = spec["size"]
		b.box(s, Vector3(0, s.y * 0.5, 0), Color("#6b3d3d"))
		b.cyl(0.16, 0.16, s.y, Vector3(-s.x * 0.3, s.y * 0.5, s.z * 0.2), Color("#7a4a4a"), MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 8)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		cs.shape = box
		cs.position = Vector3(0, s.y * 0.5, 0)
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = b.build_mesh()
		body.add_child(mi)
		add_child(body)
		_moving_walls.append(body)
		_wall_data.append({"base": spec["pos"], "axis": spec["axis"], "amp": spec["amp"], "speed": spec["speed"], "phase": rng.randf() * TAU})


func _build_obstructions() -> void:
	# sphincter barriers that close when the house is agitated
	for i in 2:
		var body := AnimatableBody3D.new()
		body.name = "Barrier%d" % i
		body.sync_to_physics = false
		body.position = Vector3(0 if i == 0 else 8.0, 0, -1.0 if i == 0 else 4.0)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 2.4, 0.4)
		cs.shape = box
		cs.position = Vector3(0, 1.2, 0)
		body.add_child(cs)
		var b := MeshBuilder.new()
		b.box(Vector3(1.6, 2.4, 0.4), Vector3(0, 1.2, 0), Color("#7a3a3a"))
		var mi := MeshInstance3D.new()
		mi.mesh = b.build_mesh()
		body.add_child(mi)
		add_child(body)
		_spasms.append(body)
		_spasm_state.append(false)
		body.position.y = -2.6


func _build_doors() -> void:
	add_door(Vector3(-0.7, 0, 9), 0.0, 1.4, 2.4, "Front Door", false, Color("#4a2a26"))
	add_door(Vector3(-4, 0, 4.0), -PI * 0.5, 1.5, 2.3, "West Chamber", false, Color("#5a3230"))
	add_door(Vector3(4, 0, 4.0), -PI * 0.5, 1.5, 2.3, "East Chamber", false, Color("#5a3230"))


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.18, Color(0.6, 0.35, 0.4), Vector3(-0.9, 0.5, 0.1))
	var l1 := add_light(Vector3(0, H - 0.4, 4.0), Color(1.0, 0.6, 0.55), 2.0, 12.0, true)
	register_flicker_light(l1)
	add_light(Vector3(-8.5, H - 0.4, 4.0), Color(1.0, 0.55, 0.5), 1.5, 10.0, true)
	add_light(Vector3(8.5, H - 0.4, 4.0), Color(1.0, 0.55, 0.5), 1.5, 10.0, true)
	add_light(Vector3(-8.5, H - 0.4, -6.0), Color(0.9, 0.5, 0.6), 1.2, 9.0)
	add_light(Vector3(8.5, H - 0.4, -6.0), Color(0.9, 0.5, 0.6), 1.2, 9.0)
	add_light(Vector3(0, H - 0.4, -6.0), Color(1.0, 0.45, 0.45), 1.4, 10.0, true)
	add_light(Vector3(0, 2.5, 9.8), Color(1.0, 0.7, 0.6), 1.2, 8.0)


func _build_furniture() -> void:
	# the house provides its own furniture, and some of it is part of the house
	add_required(["sofa_living"], Vector3(-8.5, 0.03, 6.4), PI * 0.5, "west")
	add_decor("armchair", Vector3(-11.4, 0.03, 2.4), PI * 0.5, "west")
	add_required(["wardrobe"], Vector3(-12.4, 0.03, -4.0), PI * 0.5, "west")
	add_decor("bookshelf", Vector3(-6.0, 0.03, -8.6), 0.0, "west")
	add_required(["dining_table"], Vector3(8.5, 0.03, 5.0), 0.0, "east")
	add_required(["chair_wrong"], Vector3(7.4, 0.03, 4.2), 0.3, "east")
	add_required(["chair_wrong"], Vector3(9.6, 0.03, 4.2), -0.3, "east")
	add_required(["organ"], Vector3(12.2, 0.03, -4.0), -PI * 0.5, "east")
	add_decor("mattress", Vector3(6.0, 0.03, -8.6), 0.0, "east")
	add_required(["mirror_cursed"], Vector3(0.0, 0.03, -8.4), 0.0, "hall")
	add_decor("floor_lamp", Vector3(-2.8, 0.03, 8.0), 0.0, "hall")
	add_decor("floor_lamp", Vector3(2.8, 0.03, 8.0), 0.0, "hall")
	add_optional(["doll_large"], Vector3(0.0, 0.03, 6.0), 0.0, "hall", 0.8)


func on_mission_start(_m: MissionManager) -> void:
	Audio.play_ambience("organic_breathe", 2.5)
	Audio.play_music("prop_dread", 3.0)


func mission_tick(m: MissionManager, delta: float) -> void:
	_breath += delta * (_breath_rate + _agitation * 0.18)
	_agitation = maxf(0.0, _agitation - delta * 0.15)
	var cycle := sin(_breath)
	# the floor inhales
	if _floor_body:
		_floor_body.position.y = maxf(-0.12, cycle * 0.07)
	# walls drift
	for i in _moving_walls.size():
		var data: Dictionary = _wall_data[i]
		var body := _moving_walls[i]
		var offset: Vector3 = data["axis"] * (data["amp"] * sin(_breath * float(data["speed"]) * 3.0 + float(data["phase"])))
		body.position = data["base"] + offset
	# barriers rise and fall
	for i in _spasms.size():
		var want := _agitation > 0.5 and (i % 2 == int(_breath) % 2)
		if want != _spasm_state[i]:
			_spasm_state[i] = want
			var tw := create_tween()
			tw.tween_property(_spasms[i], "position:y", 0.0 if want else -2.6, 1.6).set_trans(Tween.TRANS_SINE)
			if want:
				Audio.play_sfx("house_react", _spasms[i].global_position, -6.0)
	# players standing on the breathing floor get a gentle heave
	if not Net.is_host():
		return
	for p in Game.players_root.get_children():
		if p is Player:
			var pl := p as Player
			if absf(pl.global_position.x) < 3.6 and pl.global_position.z > -0.8 and pl.global_position.z < 8.7 and pl.is_on_floor():
				pl.velocity.y += cycle * 0.9 * delta * 60.0 * 0.06


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"breath_spasm":
			_agitation = minf(2.0, _agitation + 0.9)
			Audio.play_sfx("house_react", data.get("pos", Vector3.ZERO), -2.0)
			mission_notify("The house has taken a breath. Hold on to something.")
		"passage_close":
			for s in _spasms:
				var tw := create_tween()
				tw.tween_property(s, "position:y", 0.0, 1.0)
			mission_notify("A passage has closed. Another will open.")
		_:
			super(m, event_name, data)


func on_loud_noise(_m: MissionManager, pos: Vector3) -> void:
	_agitation = minf(2.5, _agitation + 0.7)
	Audio.play_sfx("house_react", pos, -4.0)
	mission_notify("The house heard that.")
