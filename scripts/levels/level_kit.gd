class_name LevelKit
extends RefCounted
## Construction kit shared by every property: architecture, lighting and atmosphere.
## All geometry lands in a MeshBuilder so a whole house is a handful of draw calls.

# ---------------------------------------------------------------- geometry --

static func floor_rect(mb: MeshBuilder, rect: Rect2, y: float, color: Color, thickness := 0.2) -> void:
	mb.box(Vector3(rect.size.x, thickness, rect.size.y), Vector3(rect.position.x + rect.size.x * 0.5, y - thickness * 0.5, rect.position.y + rect.size.y * 0.5), color)


static func ceiling_rect(mb: MeshBuilder, rect: Rect2, y: float, color: Color) -> void:
	mb.box(Vector3(rect.size.x, 0.16, rect.size.y), Vector3(rect.position.x + rect.size.x * 0.5, y + 0.08, rect.position.y + rect.size.y * 0.5), color)


## Wall from a to b with optional openings: [{center: float, width: float, height: float}]
static func wall(mb: MeshBuilder, a: Vector3, b: Vector3, height: float, thickness: float, color: Color, openings: Array = []) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.01:
		return
	var along := dir / length
	var yaw := atan2(-along.z, along.x)

	if openings.is_empty():
		var mid := (a + b) * 0.5
		mb.box(Vector3(length, height, thickness), Vector3(mid.x, a.y + height * 0.5, mid.z), color, MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))
		return

	var sorted := openings.duplicate()
	sorted.sort_custom(func(p, q): return float(p["center"]) < float(q["center"]))
	var cursor := 0.0
	for op in sorted:
		var ow := float(op.get("width", 1.0))
		var oh := float(op.get("height", 2.05))
		var oc := clampf(float(op["center"]), 0.0, length)
		var start := maxf(0.0, oc - ow * 0.5)
		var finish := minf(length, oc + ow * 0.5)
		if start - cursor > 0.02:
			_segment(mb, a, along, cursor, start, a.y, height, 0.0, thickness, color, yaw)
		var lintel := height - oh
		if lintel > 0.02:
			_segment(mb, a, along, start, finish, a.y + oh, lintel, 0.0, thickness, color, yaw)
		cursor = finish
	if length - cursor > 0.02:
		_segment(mb, a, along, cursor, length, a.y, height, 0.0, thickness, color, yaw)


static func _segment(mb: MeshBuilder, a: Vector3, along: Vector3, from_d: float, to_d: float, base_y: float,
		h: float, _unused: float, thickness: float, color: Color, yaw: float) -> void:
	var seg_len := to_d - from_d
	if seg_len <= 0.02:
		return
	var center := a + along * ((from_d + to_d) * 0.5)
	mb.box(Vector3(seg_len, h, thickness), Vector3(center.x, base_y + h * 0.5, center.z), color,
		MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))


static func door_frame(mb: MeshBuilder, at: Vector3, width: float, height: float, yaw: float, color: Color) -> void:
	var t := 0.13
	mb.box(Vector3(t, height + 0.1, 0.3), Vector3(at.x - width * 0.5, at.y + (height + 0.1) * 0.5, at.z), color,
		MeshBuilder.Mat.PLAIN, false, Vector3(0, yaw, 0))
	mb.box(Vector3(t, height + 0.1, 0.3), Vector3(at.x + width * 0.5, at.y + (height + 0.1) * 0.5, at.z), color,
		MeshBuilder.Mat.PLAIN, false, Vector3(0, yaw, 0))
	mb.box(Vector3(width + t, 0.13, 0.3), Vector3(at.x, at.y + height + 0.06, at.z), color,
		MeshBuilder.Mat.PLAIN, false, Vector3(0, yaw, 0))


## Window: glass pane + sill + a soft light patch so interiors read at night.
static func window_pane(parent: Node3D, at: Vector3, width: float, height: float, yaw: float, lit := false) -> void:
	var b := MeshBuilder.new()
	b.box(Vector3(width, height, 0.05), Vector3.ZERO, Color(0.22, 0.3, 0.38, 0.55), MeshBuilder.Mat.GLASS, false)
	b.box(Vector3(0.07, height, 0.09), Vector3(0, 0, 0), Color("#d8d2c4"), MeshBuilder.Mat.PLAIN, false)
	b.box(Vector3(width, 0.07, 0.09), Vector3(0, 0, 0), Color("#d8d2c4"), MeshBuilder.Mat.PLAIN, false)
	b.box(Vector3(width + 0.16, 0.09, 0.22), Vector3(0, -height * 0.5, 0.06), Color("#c8c2b4"), MeshBuilder.Mat.PLAIN, false)
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	mi.position = at
	mi.rotation.y = yaw
	parent.add_child(mi)
	if lit:
		var l := OmniLight3D.new()
		l.position = at + Vector3(0, 0, 0.4)
		l.light_color = Color(0.6, 0.72, 0.95)
		l.light_energy = 1.1
		l.omni_range = 6.0
		l.shadow_enabled = false
		parent.add_child(l)


# ---------------------------------------------------------------- lighting --

static func lamp(parent: Node3D, pos: Vector3, color := Color(1.0, 0.86, 0.65), energy := 1.6,
		light_range := 7.5, shadows := false, fixture := true) -> OmniLight3D:
	if fixture:
		var b := MeshBuilder.new()
		b.cyl(0.16, 0.22, 0.14, Vector3(0, 0.07, 0), Color("#d8d0bc"), MeshBuilder.Mat.EMISSIVE, false, Vector3.ZERO, 10)
		b.cyl(0.02, 0.02, 0.22, Vector3(0, 0.2, 0), Color("#4a4a4e"), MeshBuilder.Mat.METAL, false, Vector3.ZERO, 6)
		var mi := MeshInstance3D.new()
		mi.mesh = b.build_mesh()
		mi.position = pos
		parent.add_child(mi)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, -0.1, 0)
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.6
	l.shadow_enabled = shadows
	l.distance_fade_enabled = true
	l.distance_fade_begin = 42.0
	l.distance_fade_length = 14.0
	parent.add_child(l)
	return l


static func corridor_strip(parent: Node3D, pos: Vector3, length: float, yaw: float, color := Color(0.85, 0.9, 1.0), energy := 0.8) -> void:
	var b := MeshBuilder.new()
	b.box(Vector3(length, 0.1, 0.22), Vector3.ZERO, Color("#e8e8e0"), MeshBuilder.Mat.EMISSIVE, false)
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, -0.2, 0)
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 6.5
	l.shadow_enabled = false
	parent.add_child(l)


# ------------------------------------------------------------- environment --

static func make_environment(parent: Node3D, preset: String) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.06
	match preset:
		"suburb_night":
			env.background_color = Color(0.035, 0.045, 0.075)
			env.ambient_light_color = Color(0.32, 0.38, 0.55)
			env.ambient_light_energy = 0.55
			env.fog_light_color = Color(0.06, 0.08, 0.13)
			env.fog_density = 0.012
			env.fog_height = 1.0
		"coastal_night":
			env.background_color = Color(0.03, 0.05, 0.09)
			env.ambient_light_color = Color(0.28, 0.4, 0.55)
			env.ambient_light_energy = 0.6
			env.fog_light_color = Color(0.05, 0.09, 0.14)
			env.fog_density = 0.03
		"indoor_night":
			env.background_color = Color(0.012, 0.014, 0.02)
			env.ambient_light_color = Color(0.26, 0.28, 0.35)
			env.ambient_light_energy = 0.35
			env.fog_light_color = Color(0.03, 0.035, 0.05)
			env.fog_density = 0.018
		"indoor_luxury":
			env.background_color = Color(0.02, 0.02, 0.025)
			env.ambient_light_color = Color(0.55, 0.48, 0.4)
			env.ambient_light_energy = 0.45
			env.fog_light_color = Color(0.06, 0.05, 0.045)
			env.fog_density = 0.008
			env.adjustment_saturation = 1.12
		"organic_night":
			env.background_color = Color(0.04, 0.015, 0.02)
			env.ambient_light_color = Color(0.4, 0.24, 0.24)
			env.ambient_light_energy = 0.4
			env.fog_light_color = Color(0.09, 0.03, 0.035)
			env.fog_density = 0.045
		"last_customer":
			env.background_color = Color(0.015, 0.008, 0.02)
			env.ambient_light_color = Color(0.32, 0.24, 0.4)
			env.ambient_light_energy = 0.4
			env.fog_light_color = Color(0.05, 0.02, 0.07)
			env.fog_density = 0.035
		_:
			env.background_color = Color(0.02, 0.02, 0.03)
			env.ambient_light_color = Color(0.3, 0.3, 0.35)
			env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	return we


static func moonlight(parent: Node3D, energy := 0.55, color := Color(0.55, 0.68, 1.0), rot := Vector3(-0.85, 0.6, 0.0)) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = "Moonlight"
	l.light_energy = energy
	l.light_color = color
	l.rotation = rot
	l.shadow_enabled = true
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	l.directional_shadow_max_distance = 60.0
	l.shadow_bias = 0.04
	parent.add_child(l)
	return l


## Straight staircase between two points on different floors. Adds real collision steps,
## which is what makes carrying a wardrobe upstairs interesting.
static func stairs(mb: MeshBuilder, from: Vector3, to: Vector3, width: float, color: Color, steps := 0) -> void:
	var delta := to - from
	var rise := delta.y
	var run := Vector2(delta.x, delta.z).length()
	if steps <= 0:
		steps = maxi(4, int(rise / 0.19))
	var step_h := rise / float(steps)
	var step_d := run / float(steps)
	var along := Vector3(delta.x, 0, delta.z).normalized()
	var yaw := atan2(-along.z, along.x)
	for i in steps:
		var h := step_h * (i + 1)
		var center := from + along * (step_d * (i + 0.5))
		mb.box(Vector3(step_d + 0.02, h, width), Vector3(center.x, from.y + h * 0.5, center.z), color,
			MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))


static func railing(mb: MeshBuilder, from: Vector3, to: Vector3, height: float, color: Color) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.01:
		return
	var along := delta / length
	var yaw := atan2(-along.z, along.x)
	var mid := (from + to) * 0.5
	mb.box(Vector3(length, 0.08, 0.08), Vector3(mid.x, mid.y + height, mid.z), color, MeshBuilder.Mat.PLAIN, false, Vector3(0, yaw, 0))
	var count := maxi(2, int(length / 0.9))
	for i in count + 1:
		var p := from + along * (length * float(i) / float(count))
		mb.box(Vector3(0.06, height, 0.06), Vector3(p.x, p.y + height * 0.5, p.z), color, MeshBuilder.Mat.PLAIN, false)


static func ground_plane(parent: Node3D, size: float, color: Color, y := 0.0) -> void:
	var b := MeshBuilder.new()
	b.box(Vector3(size, 0.4, size), Vector3(0, y - 0.2, 0), color)
	b.commit_static(parent, "Ground")
