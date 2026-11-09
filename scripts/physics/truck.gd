class_name Truck
extends Node3D
## The moving truck: cargo validation, rear doors, ramp and departure point.
##
## Local space: origin at the ground under the middle of the cargo bed, +Z = rear
## (the end you load from), +X = right. The bed surface is CARGO_FLOOR_Y.
##
## An object counts as loaded when its whole footprint is inside the cargo volume and
## it has stopped moving. It counts as unloaded again if a player drags it back out --
## which happens, and is part of the comedy.

signal furniture_loaded(f: Furniture)
signal furniture_unloaded(f: Furniture)
signal capacity_warning(count: int, capacity: int)
signal doors_changed(open: bool)

const CARGO_LENGTH := 5.0
const CARGO_WIDTH := 2.6
const CARGO_HEIGHT := 2.35
const CARGO_FLOOR_Y := 0.78
const BASE_CAPACITY := 16
const SETTLE_SPEED := 0.6
const CHECK_INTERVAL := 0.25

var capacity := BASE_CAPACITY
var has_work_light := false
var doors_open := false

var cargo: Area3D
var delivered: Array[Furniture] = []
var _check_timer := 0.0
var _warned := false
var _doors_warned := false
var ramp_body: StaticBody3D
var _door_l: Door
var _door_r: Door
var _cargo_light: OmniLight3D
var _cargo_bodies: Array[StaticBody3D] = []


func setup(p_capacity := BASE_CAPACITY, p_light := false) -> void:
	capacity = p_capacity
	has_work_light = p_light


func _ready() -> void:
	_build()
	_build_cargo_area()
	_check_timer = CHECK_INTERVAL


# --------------------------------------------------------------------- build ---

func _build() -> void:
	var body_col := skin_body_color()
	var trim := skin_trim_color()
	var b := MeshBuilder.new()
	# chassis + bed skirts
	b.box(Vector3(CARGO_WIDTH + 0.1, 0.18, CARGO_LENGTH + 0.2), Vector3(0, CARGO_FLOOR_Y - 0.09, 0), Color("#2b3238"), MeshBuilder.Mat.METAL, true)
	b.box(Vector3(CARGO_WIDTH, 0.06, CARGO_LENGTH), Vector3(0, CARGO_FLOOR_Y, 0), Color("#6b6154"))
	# side walls (open box)
	b.box(Vector3(0.08, CARGO_HEIGHT, CARGO_LENGTH), Vector3(-CARGO_WIDTH * 0.5 - 0.04, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, 0), body_col, MeshBuilder.Mat.METAL, true)
	b.box(Vector3(0.08, CARGO_HEIGHT, CARGO_LENGTH), Vector3(CARGO_WIDTH * 0.5 + 0.04, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, 0), body_col, MeshBuilder.Mat.METAL, true)
	# front wall (behind the cab)
	b.box(Vector3(CARGO_WIDTH + 0.16, CARGO_HEIGHT, 0.08), Vector3(0, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, -CARGO_LENGTH * 0.5 - 0.04), body_col, MeshBuilder.Mat.METAL, true)
	# roof
	b.box(Vector3(CARGO_WIDTH + 0.16, 0.1, CARGO_LENGTH + 0.1), Vector3(0, CARGO_FLOOR_Y + CARGO_HEIGHT, 0), body_col, MeshBuilder.Mat.METAL, true)
	# door frame at the rear
	b.box(Vector3(0.12, CARGO_HEIGHT, 0.12), Vector3(-CARGO_WIDTH * 0.5, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, CARGO_LENGTH * 0.5), trim, MeshBuilder.Mat.METAL, true)
	b.box(Vector3(0.12, CARGO_HEIGHT, 0.12), Vector3(CARGO_WIDTH * 0.5, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, CARGO_LENGTH * 0.5), trim, MeshBuilder.Mat.METAL, true)
	b.box(Vector3(CARGO_WIDTH, 0.16, 0.12), Vector3(0, CARGO_FLOOR_Y + CARGO_HEIGHT - 0.08, CARGO_LENGTH * 0.5), trim, MeshBuilder.Mat.METAL, true)
	# cab
	b.box(Vector3(2.05, 1.25, 1.7), Vector3(0, 1.0, -CARGO_LENGTH * 0.5 - 1.6), skin_cab_color(), MeshBuilder.Mat.METAL, true)
	b.box(Vector3(1.95, 0.75, 0.1), Vector3(0, 1.55, -CARGO_LENGTH * 0.5 - 2.42), Color("#26303a", 0.75), MeshBuilder.Mat.GLASS)
	b.box(Vector3(0.1, 0.65, 1.4), Vector3(-1.02, 1.5, -CARGO_LENGTH * 0.5 - 1.7), Color("#26303a", 0.75), MeshBuilder.Mat.GLASS)
	b.box(Vector3(0.1, 0.65, 1.4), Vector3(1.02, 1.5, -CARGO_LENGTH * 0.5 - 1.7), Color("#26303a", 0.75), MeshBuilder.Mat.GLASS)
	# bumper, grille, lights
	b.box(Vector3(2.1, 0.22, 0.16), Vector3(0, 0.55, -CARGO_LENGTH * 0.5 - 2.5), Color("#8d949a"), MeshBuilder.Mat.METAL, true)
	b.box(Vector3(0.34, 0.16, 0.08), Vector3(-0.75, 0.92, -CARGO_LENGTH * 0.5 - 2.5), Color(1.0, 0.95, 0.8), MeshBuilder.Mat.EMISSIVE)
	b.box(Vector3(0.34, 0.16, 0.08), Vector3(0.75, 0.92, -CARGO_LENGTH * 0.5 - 2.5), Color(1.0, 0.95, 0.8), MeshBuilder.Mat.EMISSIVE)
	b.box(Vector3(0.2, 0.3, 0.08), Vector3(-0.85, 0.95, CARGO_LENGTH * 0.5 + 0.06), Color(0.9, 0.12, 0.1), MeshBuilder.Mat.EMISSIVE)
	b.box(Vector3(0.2, 0.3, 0.08), Vector3(0.85, 0.95, CARGO_LENGTH * 0.5 + 0.06), Color(0.9, 0.12, 0.1), MeshBuilder.Mat.EMISSIVE)
	# wheels
	for sx in [-1.0, 1.0]:
		for sz in [-2.1, 1.1]:
			b.cyl(0.42, 0.42, 0.28, Vector3(sx * (CARGO_WIDTH * 0.5 + 0.02), 0.42, sz), Color("#1a1c1e"), MeshBuilder.Mat.PLAIN, false, Vector3(PI * 0.5, 0, 0), 12)
	b.commit_static(self, "Body", true)

	# rear step / ramp so loaded furniture can be pushed in by a small crew
	ramp_body = StaticBody3D.new()
	ramp_body.name = "Ramp"
	ramp_body.collision_layer = Layers.WORLD
	ramp_body.collision_mask = 0
	var ramp := MeshBuilder.new()
	ramp.box(Vector3(ramp_width(), 0.08, ramp_length()), Vector3(0, 0, 0), Color("#5a5348"))
	var ramp_mesh := MeshInstance3D.new()
	ramp_mesh.mesh = ramp.build_mesh()
	ramp_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ramp_body.add_child(ramp_mesh)
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(ramp_width(), 0.08, ramp_length())
	rcs.shape = rbox
	ramp_body.add_child(rcs)
	ramp_body.position = Vector3(0, CARGO_FLOOR_Y * 0.5 - 0.02, CARGO_LENGTH * 0.5 + ramp_length() * 0.5)
	ramp_body.rotation.x = -atan2(CARGO_FLOOR_Y, ramp_length())
	add_child(ramp_body)

	# rear doors
	var dl_col := Color("#4a555d")
	_door_l = Door.new()
	_door_l.name = "DoorRearLeft"
	_door_l.position = Vector3(-CARGO_WIDTH * 0.5 + 0.06, CARGO_FLOOR_Y, CARGO_LENGTH * 0.5)
	_door_l.rotation.y = 0.0
	_door_l.swing_dir = -1.0
	add_child(_door_l)
	_door_l.setup(CARGO_WIDTH * 0.5 - 0.06, CARGO_HEIGHT - 0.08, dl_col, "Truck Door")
	_door_r = Door.new()
	_door_r.name = "DoorRearRight"
	_door_r.position = Vector3(CARGO_WIDTH * 0.5 - 0.06, CARGO_FLOOR_Y, CARGO_LENGTH * 0.5)
	_door_r.rotation.y = PI
	_door_r.swing_dir = 1.0
	add_child(_door_r)
	_door_r.setup(CARGO_WIDTH * 0.5 - 0.06, CARGO_HEIGHT - 0.08, dl_col, "Truck Door")
	_door_l.state_changed.connect(_on_door_state)
	_door_r.state_changed.connect(_on_door_state)

	# interior work light
	_cargo_light = OmniLight3D.new()
	_cargo_light.light_color = Color(1.0, 0.92, 0.78)
	_cargo_light.light_energy = 1.9 if has_work_light else 0.0
	_cargo_light.omni_range = 4.6
	_cargo_light.shadow_enabled = false
	_cargo_light.position = Vector3(0, CARGO_FLOOR_Y + CARGO_HEIGHT - 0.25, 0)
	add_child(_cargo_light)

	# company branding
	var label := Label3D.new()
	label.text = "LAST MOVE\nMOVING & STORAGE"
	label.font_size = 44
	label.pixel_size = 0.005
	label.modulate = Color("#e8e2d0")
	label.position = Vector3(-CARGO_WIDTH * 0.5 - 0.06, CARGO_FLOOR_Y + 1.3, 0)
	label.rotation = Vector3(0, -PI * 0.5, 0)
	add_child(label)
	var label2 := label.duplicate() as Label3D
	label2.position = Vector3(CARGO_WIDTH * 0.5 + 0.06, CARGO_FLOOR_Y + 1.3, 0)
	label2.rotation = Vector3(0, PI * 0.5, 0)
	add_child(label2)


func _build_cargo_area() -> void:
	cargo = Area3D.new()
	cargo.name = "CargoZone"
	cargo.collision_layer = Layers.TRIGGER
	cargo.collision_mask = Layers.FURNITURE
	cargo.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CARGO_WIDTH - 0.04, CARGO_HEIGHT - 0.1, CARGO_LENGTH - 0.04)
	cs.shape = box
	cs.position = Vector3(0, CARGO_FLOOR_Y + CARGO_HEIGHT * 0.5, 0)
	cargo.add_child(cs)
	add_child(cargo)


func _on_door_state(_open: bool) -> void:
	var now := _door_l.is_open and _door_r.is_open
	if now != doors_open:
		doors_open = now
		doors_changed.emit(doors_open)


func set_doors(open: bool) -> void:
	if _door_l == null:
		return
	if open:
		if not _door_l.is_open:
			_door_l.toggle()
		if not _door_r.is_open:
			_door_r.toggle()
	else:
		if _door_l.is_open:
			_door_l.toggle()
		if _door_r.is_open:
			_door_r.toggle()


func open_one_door() -> void:
	# one door open is enough for the crew to squeeze a side table through, not a sofa
	if _door_l and _door_r:
		if not _door_r.is_open:
			_door_r.toggle()
		elif not _door_l.is_open:
			_door_l.toggle()


# ------------------------------------------------------------------ validation ---

func _physics_process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_INTERVAL
	if not Net.is_host():
		return
	_validate_cargo()


func cargo_bounds() -> AABB:
	return AABB(
		Vector3(-CARGO_WIDTH * 0.5 + 0.06, CARGO_FLOOR_Y - 0.12, -CARGO_LENGTH * 0.5 + 0.06),
		Vector3(CARGO_WIDTH - 0.12, CARGO_HEIGHT - 0.16, CARGO_LENGTH - 0.12))


## True when the whole footprint of the object is inside the cargo volume.
func is_inside_cargo(f: Furniture) -> bool:
	if f == null or not is_instance_valid(f):
		return false
	var local := to_local(f.global_position)
	var half := f.size * 0.5
	var b := cargo_bounds()
	# conservative: the object must fit with its largest horizontal half-extent
	var half_h := maxf(half.x, half.z) * 0.92
	return (
		local.x - half_h >= b.position.x - 0.05 and local.x + half_h <= b.position.x + b.size.x + 0.05
		and local.z - half_h >= b.position.z - 0.05 and local.z + half_h <= b.position.z + b.size.z + 0.05
		and local.y + half.y <= b.position.y + b.size.y + 0.45
		and local.y >= b.position.y - 0.5
	)


func _validate_cargo() -> void:
	# Nothing counts as loaded while the rear doors are shut: the validation is "inside
	# the cargo bay with the doors open", which is why the doors matter at all.
	if not doors_open:
		_warn_doors_once()
		return
	var mission := Game.mission
	if mission == null:
		return
	for f in mission.furniture:
		if not is_instance_valid(f) or not f.is_alive:
			continue
		var inside := is_inside_cargo(f) and f.linear_velocity.length() < _settle_speed() and not f.is_held()
		if inside and not f.delivered:
			_deliver(f)
		elif not inside and f.delivered:
			_undeliver(f)
	var count := delivered.size()
	if count >= capacity and not _warned:
		_warned = true
		capacity_warning.emit(count, capacity)


func _warn_doors_once() -> void:
	if _doors_warned:
		return
	_doors_warned = true
	Audio.play_sfx("door_locked", global_position, -10.0)
	get_tree().create_timer(20.0).timeout.connect(func(): _doors_warned = false)


## Truck skin: the paint upgrades are read here, so "Company Paint Job" actually repaints the
## truck instead of only taking the crew's money.
func skin_level() -> int:
	if Save.owns_upgrade("paint_company"):
		return 1
	return 0


func skin_body_color() -> Color:
	return Color("#2f6f4f") if skin_level() == 1 else Color("#3f4a52")


func skin_cab_color() -> Color:
	return Color("#357f5b") if skin_level() == 1 else Color("#4d5b63")


func skin_trim_color() -> Color:
	return Color("#d8d2b8") if skin_level() == 1 else Color("#c8c2b2")


## Portable Ramp upgrade: a longer, wider plate means a shallower climb for pushed loads.
func ramp_length() -> float:
	return 2.6 if Save.owns_upgrade("ramp") else 1.9


func ramp_width() -> float:
	return CARGO_WIDTH if Save.owns_upgrade("ramp") else CARGO_WIDTH * 0.86


## Cargo Straps upgrade: a lashed load counts as stowed while it is still rocking.
func _settle_speed() -> float:
	return SETTLE_SPEED * 1.5 if Save.owns_upgrade("truck_organize") else SETTLE_SPEED


func has_room_for(f: Furniture) -> bool:
	# contracted items always fit; the hold is only too full for extras
	return f.is_required or delivered.size() < capacity


func _deliver(f: Furniture) -> void:
	if not has_room_for(f):
		return
	f.set_delivered(true)
	delivered.append(f)
	Audio.play_sfx("truck_load", f.global_position, -2.0)
	furniture_loaded.emit(f)
	if delivered.size() > capacity:
		capacity_warning.emit(delivered.size(), capacity)


func _undeliver(f: Furniture) -> void:
	f.set_delivered(false)
	delivered.erase(f)
	furniture_unloaded.emit(f)
	Audio.play_sfx("truck_door", f.global_position, -8.0)


# --------------------------------------------------------------------- points ---

func interior_point() -> Vector3:
	return to_global(Vector3(0, CARGO_FLOOR_Y + 1.0, 0))


func depart_point() -> Vector3:
	# standing beside the cab, where the "leave" interaction lives
	return to_global(Vector3(-1.9, 0.1, -CARGO_LENGTH * 0.5 - 1.2))


func player_spawn_point() -> Vector3:
	return to_global(Vector3(0, 0.12, CARGO_LENGTH * 0.5 + 4.2))


func load_point() -> Vector3:
	return to_global(Vector3(0, 0.1, CARGO_LENGTH * 0.5 + 3.2))


func cargo_screen_position(camera: Camera3D) -> Vector2:
	return camera.unproject_position(interior_point())


func summary() -> String:
	return "%d / %d" % [delivered.size(), capacity]
