class_name Door
extends AnimatableBody3D
## A hinged door. The node origin is the HINGE, so rotating rotation.y swings the leaf.
## Doors are real obstacles: furniture must fit through them, they can be shoved open by
## heavy objects, and misjudged angles are a reliable source of comedy.

signal state_changed(open: bool)

var width := 0.95
var height := 2.05
var thickness := 0.06
var is_open := false
var locked := false
var display_label := "Door"
var color := Color("#7a5a3f")
var swing_dir := 1.0
var auto_close_time := 0.0
var slam_on_close := false

var _area: Area3D
var _tween: Tween
var _close_timer := 0.0
var _bodies_inside := 0
var _start_rotation := 0.0


func setup(w: float, h: float, p_color: Color, label := "Door") -> void:
	width = w
	height = h
	color = p_color
	display_label = label
	_build()


func _build() -> void:
	collision_layer = Layers.DOOR
	collision_mask = Layers.FURNITURE | Layers.PLAYER | Layers.CREATURE
	sync_to_physics = false
	_start_rotation = rotation.y

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, thickness)
	cs.shape = box
	cs.position = Vector3(width * 0.5, height * 0.5, 0)
	add_child(cs)

	var b := MeshBuilder.new()
	b.box(Vector3(width, height, thickness), Vector3(width * 0.5, height * 0.5, 0), color)
	# panels
	b.box(Vector3(width * 0.62, height * 0.3, thickness * 0.4), Vector3(width * 0.5, height * 0.72, 0), color.lightened(0.06), MeshBuilder.Mat.PLAIN, false)
	b.box(Vector3(width * 0.62, height * 0.3, thickness * 0.4), Vector3(width * 0.5, height * 0.28, 0), color.lightened(0.06), MeshBuilder.Mat.PLAIN, false)
	# handle + hinges
	b.box(Vector3(0.05, 0.05, 0.16), Vector3(width * 0.86, height * 0.5, thickness * 0.5), Color("#c8a24a"), MeshBuilder.Mat.METAL, false)
	b.box(Vector3(0.05, 0.05, 0.16), Vector3(width * 0.86, height * 0.5, -thickness * 0.5), Color("#c8a24a"), MeshBuilder.Mat.METAL, false)
	for i in 2:
		b.box(Vector3(0.1, 0.06, thickness * 1.2), Vector3(0.03, height * (0.2 + 0.6 * i), 0), Color("#6a6a6e"), MeshBuilder.Mat.METAL, false)
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	add_child(mi)

	_area = Area3D.new()
	_area.name = "ShoveArea"
	_area.collision_layer = 0
	_area.collision_mask = Layers.FURNITURE | Layers.CREATURE
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	# The volume must extend past the leaf on both faces: a body that hits the leaf is
	# *stopped* by it, so a thin slab centred on the leaf would never register a shove.
	abox.size = Vector3(width * 1.05, height * 0.9, 1.3)
	acs.shape = abox
	acs.position = Vector3(width * 0.5, height * 0.5, 0)
	_area.add_child(acs)
	add_child(_area)
	_area.body_entered.connect(_on_shove_enter)
	_area.body_exited.connect(_on_shove_exit)


func _on_shove_enter(body: Node) -> void:
	_bodies_inside += 1
	if body is Furniture and not is_open and not locked:
		var f := body as Furniture
		var impact := f.linear_velocity.length()
		if impact > 0.4 or f.is_held():
			open_door(true)


func _on_shove_exit(_body: Node) -> void:
	_bodies_inside = maxi(0, _bodies_inside - 1)
	if _bodies_inside == 0 and auto_close_time > 0.0:
		_close_timer = auto_close_time


func _process(delta: float) -> void:
	if _close_timer > 0.0 and _bodies_inside == 0:
		_close_timer -= delta
		if _close_timer <= 0.0 and is_open:
			open_door(false)


func toggle() -> void:
	if locked:
		Audio.play_sfx("door_locked", global_position, -4.0)
		return
	open_door(not is_open)


func open_door(open: bool, instant := false) -> void:
	if is_open == open:
		return
	is_open = open
	state_changed.emit(is_open)
	var target := _start_rotation + (swing_dir * deg_to_rad(102.0) if open else 0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	if instant:
		rotation.y = target
		return
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_BACK if not slam_on_close else Tween.TRANS_QUAD)
	_tween.tween_property(self, "rotation:y", target, 0.45 if open else 0.32)
	Audio.play_sfx("door_open" if open else "door_close", global_position, -6.0, randf_range(0.94, 1.06))


func slam() -> void:
	slam_on_close = true
	open_door(false)
	Audio.play_sfx("door_slam", global_position, 2.0)
	Game.report_noise(global_position, 1.0)
	await get_tree().create_timer(0.4).timeout
	slam_on_close = false
