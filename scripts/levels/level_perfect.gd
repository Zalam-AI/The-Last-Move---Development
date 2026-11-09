extends PropertyBase
## PROPERTY 05 - THE PERFECT HOME
##
## Immaculate, expensive, and watching. Every scratch is invoiced twice. The house reacts
## to damage and disorder: lights go out, doors close themselves, and eventually the house
## starts *tidying up* -- returning furniture to where it belongs, including the piece the
## crew is currently carrying.

const H := 3.2
const T := 0.22

var _irritation := 0.0
var _last_irritation_stage := 0
var _restore_timer := 0.0
var _audit_timer := 0.0
var _original_positions: Dictionary = {}


func build() -> void:
	wall_color = Color("#c9bda8")
	floor_color = Color("#8d7a5f")
	ceiling_color = Color("#efe9dc")
	LevelKit.ground_plane(self, 120.0, Color("#242a26"), 0.0)
	_build_shell()
	_build_doors()
	_build_lighting()
	_build_furniture()
	add_mission_props(Vector3(0, 0.9, 19.4), Vector3(1.4, 1.2, 10.4))
	truck_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 16.0))
	player_spawns = [
		Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 10.4)),
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(-2.4, 0.1, 11.2)),
		Transform3D(Basis(Vector3.UP, -0.4), Vector3(2.4, 0.1, 11.2)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.1, 12.4)),
	]
	event_pool = ["light_flicker", "door_close", "restoration", "light_flicker", "restoration"]


func _build_shell() -> void:
	var wc := wall_color
	# footprint x -16..16, z -12..10
	add_floor(Rect2(-16, -12, 32, 22))
	add_ceiling(Rect2(-16, -12, 32, 22), H)
	add_wall(Vector3(-16, 0, 10), Vector3(16, 0, 10), H, T, [{"center": 16.0, "width": 1.6, "height": 2.6}], wc)
	add_wall(Vector3(-16, 0, -12), Vector3(16, 0, -12), H, T, [], wc)
	add_wall(Vector3(-16, 0, -12), Vector3(-16, 0, 10), H, T, [], wc)
	add_wall(Vector3(16, 0, -12), Vector3(16, 0, 10), H, T, [], wc)
	# grand foyer down the middle
	LevelKit.wall(geo, Vector3(-5, 0, -3), Vector3(-5, 0, 10), H, T, wc,
		[{"center": 8.0, "width": 1.6, "height": 2.5}])
	LevelKit.wall(geo, Vector3(5, 0, -3), Vector3(5, 0, 10), H, T, wc,
		[{"center": 8.0, "width": 1.6, "height": 2.5}])
	LevelKit.wall(geo, Vector3(-16, 0, -3), Vector3(16, 0, -3), H, T, wc,
		[{"center": 16.0, "width": 1.8, "height": 2.5}, {"center": 6.0, "width": 1.2, "height": 2.4}])
	# east gallery corridor
	LevelKit.wall(geo, Vector3(8, 0, -12), Vector3(8, 0, -3), H, T, wc,
		[{"center": 4.5, "width": 1.3, "height": 2.4}])
	# west lounge / master suite divider
	LevelKit.wall(geo, Vector3(-8, 0, -12), Vector3(-8, 0, -3), H, T, wc,
		[{"center": 4.5, "width": 1.3, "height": 2.4}])
	# marble floor in the foyer, runner in the gallery
	geo.box(Vector3(9.6, 0.02, 13.0), Vector3(0, 0.012, 3.5), Color("#d8d2c4"))
	geo.box(Vector3(1.6, 0.03, 8.0), Vector3(8.0, 0.02, -7.0), Color("#7a3a2a"))
	geo.box(Vector3(14.0, 0.02, 6.0), Vector3(-11.0, 0.012, -7.0), Color("#5f4f3c"))
	geo.box(Vector3(14.0, 0.02, 7.0), Vector3(11.5, 0.012, 3.0), Color("#6b5a44"))
	# columns in the foyer
	for sx in [-1.0, 1.0]:
		for i in 3:
			geo.cyl(0.22, 0.26, H, Vector3(sx * 4.2, H * 0.5, -1.0 + i * 4.0), Color("#e8e2d4"),
				MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 12)
	# chandelier shapes
	for i in 2:
		geo.cyl(0.6, 0.9, 0.18, Vector3(0, H - 0.6, 1.0 + i * 6.0), Color(1.0, 0.92, 0.72), MeshBuilder.Mat.EMISSIVE)
	# front steps
	geo.box(Vector3(6.0, 0.14, 2.0), Vector3(0, 0.07, 11.0), Color("#b8b0a0"))
	geo.box(Vector3(4.0, 0.12, 1.0), Vector3(0, 0.06, 12.0), Color("#aca494"))


func _build_doors() -> void:
	add_door(Vector3(-0.8, 0, 10), 0.0, 1.6, 2.6, "Front Door", false, Color("#3a2c22"))
	add_door(Vector3(-5, 0, 1.2), -PI * 0.5, 1.6, 2.5, "West Wing", false, Color("#4a3626"))
	add_door(Vector3(5, 0, 1.2), -PI * 0.5, 1.6, 2.5, "East Wing", false, Color("#4a3626"))
	add_door(Vector3(-2.0, 0, -3), 0.0, 1.2, 2.4, "Study", false, Color("#4a3626"))
	add_door(Vector3(-11.0, 0, -3), 0.0, 1.3, 2.4, "Master Suite", false, Color("#4a3626"))
	add_door(Vector3(11.0, 0, -3), 0.0, 1.3, 2.4, "Gallery", false, Color("#4a3626"))


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.3, Color(0.55, 0.65, 0.95), Vector3(-0.95, 0.5, 0.1))
	var l := add_light(Vector3(0, H - 0.9, 1.0), Color(1.0, 0.9, 0.72), 2.6, 13.0, true)
	register_flicker_light(l)
	add_light(Vector3(0, H - 0.9, 7.0), Color(1.0, 0.9, 0.72), 2.2, 11.0, true)
	add_light(Vector3(-11, H - 0.4, 2.0), Color(1.0, 0.86, 0.66), 1.8, 10.0, true)
	add_light(Vector3(11.5, H - 0.4, 3.0), Color(1.0, 0.86, 0.66), 1.8, 10.0, true)
	add_light(Vector3(-11, H - 0.4, -7.0), Color(1.0, 0.82, 0.62), 1.4, 9.0)
	add_light(Vector3(8, H - 0.4, -7.0), Color(1.0, 0.8, 0.6), 1.2, 9.0)
	add_light(Vector3(0, 2.8, 10.8), Color(1.0, 0.9, 0.7), 1.8, 10.0, true)


func _build_furniture() -> void:
	# foyer
	add_required(["piano_grand"], Vector3(-2.6, 0.03, 5.0), PI * 0.5, "foyer")
	add_decor("vase_ceramic", Vector3(2.4, 1.0, 2.0), 0.0, "foyer")
	add_decor("plant", Vector3(4.2, 0.03, 8.6), 0.0, "foyer")
	add_decor("plant", Vector3(-4.2, 0.03, 8.6), 0.0, "foyer")
	add_required(["mirror_tall"], Vector3(3.4, 0.03, 0.6), -PI * 0.5, "foyer")
	# west lounge
	add_required(["sofa_three", "sofa_two"], Vector3(-14.6, 0.03, 4.0), PI * 0.5, "lounge")
	add_decor("coffee_table", Vector3(-12.0, 0.03, 4.0), 0.0, "lounge")
	add_decor("armchair", Vector3(-12.0, 0.03, 7.4), PI, "lounge")
	add_required(["sideboard"], Vector3(-11.0, 0.03, 9.4), PI, "lounge")
	add_decor("floor_lamp", Vector3(-15.4, 0.03, 8.4), 0.0, "lounge")
	# master suite
	add_decor("bed_frame", Vector3(-11.0, 0.03, -8.6), 0.0, "master")
	add_decor("mattress", Vector3(-11.0, 0.6, -8.6), 0.0, "master")
	add_required(["wardrobe_antique"], Vector3(-15.4, 0.03, -6.0), PI * 0.5, "master")
	add_required(["dresser"], Vector3(-6.6, 0.03, -9.0), PI * 0.5, "master")
	add_decor("mirror_tall", Vector3(-8.6, 0.03, -4.4), PI, "master")
	# gallery: the red runner corridor with delicate things in it
	add_required(["painting_framed"], Vector3(7.0, 0.03, -6.0), -PI * 0.5, "gallery")
	add_required(["painting_framed"], Vector3(7.0, 0.03, -9.0), -PI * 0.5, "gallery")
	add_decor("grandfather_clock", Vector3(9.0, 0.03, -11.0), 0.0, "gallery")
	add_required(["vase_ceramic"], Vector3(9.0, 0.03, -4.4), 0.0, "gallery")
	# study
	add_decor("desk", Vector3(-2.0, 0.03, -7.0), 0.0, "study")
	add_decor("bookshelf", Vector3(-4.6, 0.03, -11.4), 0.0, "study")
	add_decor("books_stack", Vector3(-2.0, 0.78, -7.0), 0.4, "study")
	# dining
	add_required(["dining_table"], Vector3(11.5, 0.03, 5.0), 0.0, "dining")
	add_required(["dining_chair"], Vector3(10.5, 0.03, 4.2), 0.3, "dining")
	add_required(["dining_chair"], Vector3(12.5, 0.03, 4.2), -0.3, "dining")
	add_required(["dining_chair"], Vector3(10.5, 0.03, 5.8), 2.8, "dining")
	add_required(["dining_chair"], Vector3(12.5, 0.03, 5.8), -2.8, "dining")
	add_decor("sideboard", Vector3(15.0, 0.03, 1.0), -PI * 0.5, "dining")


func on_mission_start(m: MissionManager) -> void:
	Audio.play_ambience("mansion_quiet", 2.5)
	Audio.play_music("prop_tension", 3.0)
	_original_positions.clear()
	for f in m.furniture:
		if is_instance_valid(f):
			_original_positions[f.uid] = f.global_transform
			f.damaged.connect(_on_any_damage)


func _on_any_damage(_amount: float, _destroyed: bool) -> void:
	_irritation += 1.0


func mission_tick(m: MissionManager, delta: float) -> void:
	if not Net.is_host():
		return
	# the house audits its own furniture four times a second, not sixty
	_audit_timer -= delta
	if _audit_timer > 0.0:
		return
	_audit_timer = 0.25
	# disorder also counts as damage: things out of place annoy the house
	var out_of_place := 0
	for f in m.furniture:
		if not is_instance_valid(f) or f.delivered:
			continue
		var orig: Transform3D = _original_positions.get(f.uid, f.global_transform)
		if f.global_position.distance_to(orig.origin) > 1.4:
			out_of_place += 1
	_irritation = maxf(_irritation, float(out_of_place) * 0.6 + m.property_damage * 0.02)
	var stage := 0
	if _irritation > 6.0:
		stage = 1
	if _irritation > 14.0:
		stage = 2
	if _irritation > 26.0:
		stage = 3
	if stage > _last_irritation_stage:
		_last_irritation_stage = stage
		_escalate(m, stage)
	if stage >= 2:
		_restore_timer -= 0.25
		if _restore_timer <= 0.0:
			_restore_timer = 38.0
			_restore_house(m)


func _escalate(m: MissionManager, stage: int) -> void:
	match stage:
		1:
			Audio.play_sfx("house_react", Vector3.ZERO, -6.0)
			mission_notify("The house has noticed the mess.")
			_flicker_lights()
		2:
			mission_notify("The house is correcting you.")
			Audio.play_sfx("house_creak", Vector3.ZERO, -3.0)
			for d in doors:
				if d.is_open and rng.randf() < 0.6:
					d.slam()
		3:
			mission_notify("The house has begun restoring itself. Do not help it.")
			_restore_house(m)


func _restore_house(m: MissionManager) -> void:
	var moved := 0
	for f in m.furniture:
		if not is_instance_valid(f) or f.delivered or f.is_held() or not f.is_alive:
			continue
		var orig: Transform3D = _original_positions.get(f.uid, f.global_transform)
		if f.global_position.distance_to(orig.origin) < 1.2:
			continue
		f.global_transform = orig
		f.linear_velocity = Vector3.ZERO
		f.angular_velocity = Vector3.ZERO
		Audio.play_sfx("house_creak", orig.origin, -8.0)
		moved += 1
		if moved >= 2:
			break
	if moved > 0:
		m.trigger_event("restoration", {})
		mission_notify("The furniture has been returned to its proper place.")


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"restoration":
			_restore_house(m)
		_:
			super(m, event_name, data)


func on_loud_noise(m: MissionManager, pos: Vector3) -> void:
	_irritation += 1.5
	Audio.play_sfx("house_react", pos, -8.0)
	_flicker_lights()
	if _irritation > 10.0 and rng.randf() < 0.3:
		_restore_house(m)
