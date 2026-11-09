class_name PropertyBase
extends Node3D
## Base class for every handcrafted property. Subclasses build architecture, lighting,
## doors, decorative props and the spawn list used to generate contracts. Systems code
## never knows the difference between properties -- only this interface.

var mission: MissionManager
var def: Dictionary = {}
var rng: RandomNumberGenerator
var spawns: Array[Dictionary] = []
var player_spawns: Array[Transform3D] = []
var truck_transform := Transform3D(Basis.IDENTITY, Vector3(0, 0, 10))
var event_pool: Array[String] = []
var doors: Array[Door] = []
var geo: MeshBuilder
var decor_root: Node3D

var wall_color := Color("#8a8175")
var floor_color := Color("#6a5a48")
var ceiling_color := Color("#cfc8bc")


func setup(p_mission: MissionManager, p_def: Dictionary, p_rng: RandomNumberGenerator) -> void:
	mission = p_mission
	def = p_def
	rng = p_rng
	geo = MeshBuilder.new()
	decor_root = Node3D.new()
	decor_root.name = "Decor"
	add_child(decor_root)
	build()
	commit_geometry()


# --------------------------------------------------------------- overrides --

func build() -> void:
	pass


func on_mission_start(_m: MissionManager) -> void:
	pass


func mission_tick(_m: MissionManager, _delta: float) -> void:
	pass


func on_loud_noise(_m: MissionManager, _pos: Vector3) -> void:
	pass


func on_living_furniture(_m: MissionManager, _f: Furniture) -> void:
	pass


func handle_event(m: MissionManager, event_name: String, data: Dictionary) -> void:
	match event_name:
		"light_flicker":
			_flicker_lights()
		"door_close":
			_slam_random_door()
		"radio_on":
			Audio.play_sfx("radio_static", data.get("pos", global_position), -4.0)
		_:
			pass


# ---------------------------------------------------------------- helpers ---

func add_spawn(candidates: Array, pos: Vector3, yaw: float, room: String, required := false, chance := 1.0) -> void:
	spawns.append({
		"candidates": candidates,
		"pos": pos,
		"rot": yaw,
		"room": room,
		"required": required,
		"chance": chance,
	})


func add_required(candidates: Array, pos: Vector3, yaw: float, room: String) -> void:
	add_spawn(candidates, pos, yaw, room, true, 1.0)


func add_optional(candidates: Array, pos: Vector3, yaw: float, room: String, chance := 0.75) -> void:
	spawns.append({
		"candidates": candidates, "pos": pos, "rot": yaw, "room": room,
		"required": false, "contract_optional": true, "chance": chance,
	})


func add_decor(item_id: String, pos: Vector3, yaw: float, room := "") -> void:
	spawns.append({
		"candidates": [item_id], "pos": pos, "rot": yaw, "room": room,
		"required": false, "contract_optional": false, "chance": 1.0,
	})


func add_floor(rect: Rect2, y := 0.0) -> void:
	LevelKit.floor_rect(geo, rect, y, floor_color)


func add_ceiling(rect: Rect2, y: float) -> void:
	LevelKit.ceiling_rect(geo, rect, y, ceiling_color)


func add_wall(a: Vector3, b: Vector3, height: float, thickness := 0.2, openings: Array = [], color := Color.TRANSPARENT) -> void:
	LevelKit.wall(geo, a, b, height, thickness, color if color.a > 0.0 else wall_color, openings)


func add_door(pos: Vector3, yaw: float, width: float, height: float, label: String, locked := false, color := Color("#7a5a3f")) -> Door:
	var d := Door.new()
	d.name = "Door_%s" % label.replace(" ", "_")
	d.position = pos
	d.rotation.y = yaw
	d.setup(width, height, color, label)
	d.locked = locked
	d.swing_dir = -1.0 if bool(rng.randi() % 2) else 1.0
	d._start_rotation = d.rotation.y
	add_child(d)
	doors.append(d)
	return d


func add_light(pos: Vector3, color := Color(1.0, 0.86, 0.65), energy := 1.5, light_range := 7.0, shadows := false) -> OmniLight3D:
	return LevelKit.lamp(self, pos, color, energy, light_range, shadows)


func commit_geometry(name := "Architecture") -> void:
	geo.commit_static(self, name, true)


# ------------------------------------------------------- shared behaviours ---

var _flicker_targets: Array[OmniLight3D] = []
var _portals: Array[Dictionary] = []
var _portal_cooldowns: Dictionary = {}


func register_flicker_light(l: OmniLight3D) -> void:
	_flicker_targets.append(l)


func _flicker_lights() -> void:
	if _flicker_targets.is_empty():
		return
	var l: OmniLight3D = _flicker_targets[rng.randi() % _flicker_targets.size()]
	var base := l.light_energy
	var tw := create_tween()
	if bool(Settings.get_value("reduce_flashing", false)):
		l.light_energy = base * 0.35
		tw.tween_interval(1.2)
		tw.tween_callback(func(): l.light_energy = base)
		return
	for i in 5:
		tw.tween_property(l, "light_energy", base * randf_range(0.1, 0.4), 0.06)
		tw.tween_property(l, "light_energy", base, 0.08)
	Audio.play_sfx("light_buzz", l.global_position, -10.0)


func _slam_random_door() -> void:
	if doors.is_empty():
		return
	var d: Door = doors[rng.randi() % doors.size()]
	if d.is_open:
		d.slam()


## Small objects that the property likes to move around when nobody is watching.
func shuffle_small_objects(m: MissionManager) -> int:
	var moved := 0
	for f in m.furniture:
		if not is_instance_valid(f) or f.is_held() or f.delivered:
			continue
		if f.weight > 6.0:
			continue
		if rng.randf() > 0.4:
			continue
		var near_player := false
		for pid in Net.players.keys():
			var p := Game.get_player(int(pid))
			if p and p.global_position.distance_to(f.global_position) < 4.0:
				near_player = true
				break
		if near_player:
			continue
		f.global_position += Vector3(rng.randf_range(-0.6, 0.6), 0.05, rng.randf_range(-0.6, 0.6))
		moved += 1
	return moved


# ------------------------------------------------------- shared furniture ---

## Adds the "clock out" point by the truck and a contract board inside the property.
func add_mission_props(depart_pos: Vector3, board_pos: Vector3, board_yaw := 0.0) -> void:
	var depart := Interactable.new()
	depart.name = "DepartPoint"
	depart.setup("Clock Out  •  End Contract", "[E] depart with the crew", depart_pos, Vector3(1.1, 1.0, 1.1))
	depart.activated.connect(func(_p): if mission: mission.request_departure())
	add_child(depart)
	var board := Interactable.new()
	board.name = "ContractBoard"
	board.setup("Contract", "[E] re-read the contract", board_pos, Vector3(0.6, 0.8, 0.4))
	board.activated.connect(func(_p): Game.ui.open_contract())
	add_child(board)
	var b := MeshBuilder.new()
	b.box(Vector3(0.9, 0.7, 0.06), board_pos + Vector3(0, 0, 0.02), Color("#e8e2d2"), MeshBuilder.Mat.PLAIN, false, Vector3(0, board_yaw, 0))
	b.box(Vector3(1.0, 0.8, 0.04), board_pos, Color("#6b4a33"), MeshBuilder.Mat.PLAIN, false, Vector3(0, board_yaw, 0))
	b.commit_static(self, "BoardVisual", false)


# ---------------------------------------------------------------- portals ---

## Creates a doorway portal: entering the trigger moves the player (and whatever they
## are carrying) to `target`. Used by the impossible-architecture properties.
func add_portal(at: Vector3, extents: Vector3, target: Transform3D, label := "") -> Area3D:
	var area := Area3D.new()
	area.name = "Portal_%d" % _portals.size()
	area.position = at
	area.collision_layer = Layers.TRIGGER
	area.collision_mask = Layers.PLAYER
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	cs.shape = box
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_portal_body.bind(_portals.size()))
	_portals.append({"area": area, "target": target, "label": label})
	if label != "":
		var l := Label3D.new()
		l.text = label
		l.font_size = 44
		l.pixel_size = 0.004
		l.modulate = Color("#d8cba8")
		l.position = at + Vector3(0, extents.y * 0.5 + 0.25, 0)
		add_child(l)
	return area


func set_portal_target(index: int, target: Transform3D, label := "") -> void:
	if index < 0 or index >= _portals.size():
		return
	_portals[index]["target"] = target
	if label != "":
		_portals[index]["label"] = label


func portal_count() -> int:
	return _portals.size()


func _on_portal_body(body: Node, index: int) -> void:
	if not (body is Player):
		return
	var p := body as Player
	var now := Time.get_ticks_msec()
	if _portal_cooldowns.has(p.peer_id) and now - int(_portal_cooldowns[p.peer_id]) < 900:
		return
	_portal_cooldowns[p.peer_id] = now
	var target: Transform3D = _portals[index]["target"]
	var offset := target.origin - p.global_position
	p.global_position = target.origin
	p.velocity = Vector3.ZERO
	if p.carried != null and is_instance_valid(p.carried):
		p.carried.global_position += offset
		if p.carried.is_held():
			pass
	Audio.play_sfx("portal", target.origin, -6.0)
	mission_notify("The house has moved you somewhere else.")


func mission_notify(text: String) -> void:
	if mission != null and Game.ui != null:
		Game.ui.notify(text, "spooky")
