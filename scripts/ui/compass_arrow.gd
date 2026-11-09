class_name CompassArrow
extends Control
## Small HUD compass that rotates toward the truck. Drawn in code so it needs no art.

var angle := 0.0
var distance := 0.0
var active := false
var color := Color("#e8b13a")


func _ready() -> void:
	custom_minimum_size = Vector2(120, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_bearing(world_dir: Vector3, camera: Camera3D, dist: float) -> void:
	active = camera != null
	if camera == null:
		return
	var fwd := -camera.global_transform.basis.z
	var flat_fwd := Vector2(fwd.x, fwd.z).normalized()
	var flat_dir := Vector2(world_dir.x, world_dir.z).normalized()
	if flat_dir.length() < 0.01:
		return
	angle = flat_fwd.angle_to(flat_dir)
	distance = dist
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var c := size * 0.5
	var r := 46.0
	draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.18), 2.0, true)
	var dir := Vector2(sin(angle), -cos(angle))
	var tip := c + dir * r
	var left := c + dir.rotated(0.42) * (r - 16.0)
	var right := c + dir.rotated(-0.42) * (r - 16.0)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
	var font := ThemeDB.fallback_font
	var label := "%d m" % int(distance)
	draw_string(font, c + Vector2(-16, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
