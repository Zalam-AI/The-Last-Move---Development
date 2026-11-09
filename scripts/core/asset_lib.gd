class_name AssetLib
extends RefCounted
## Procedural art library.
##
## Every furniture item in the game is assembled from primitives into a single merged
## mesh (one or two surfaces) plus simplified box collision. This keeps the art style
## coherent, the draw-call count low, and means the repository contains no third-party
## art with unclear licensing. All models are original procedural work by the studio.
##
## Convention: item origin is the centre of the footprint at FLOOR level (y = 0 is the
## bottom of the furniture). +Z is the front of the object.

static var _mats := {}


static func material_for(kind: int) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match kind:
		MeshBuilder.Mat.METAL:
			m.metallic = 0.85
			m.roughness = 0.38
		MeshBuilder.Mat.GLASS:
			m.metallic = 0.92
			m.roughness = 0.06
		MeshBuilder.Mat.EMISSIVE:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.88, 0.68)
			m.emission_energy_multiplier = 1.1
			m.roughness = 0.5
		_:
			m.roughness = 0.82
			m.metallic = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	_mats[kind] = m
	return m


static func build(item: Dictionary) -> MeshBuilder:
	var b := MeshBuilder.new()
	var size: Vector3 = item.get("size_v", Vector3(1, 1, 1))
	var c: Color = item.get("color_c", Color.GRAY)
	var a: Color = item.get("accent_c", c.darkened(0.2))
	var template: String = item.get("template", "crate")
	match template:
		"couch": _couch(b, size, c, a, 3)
		"armchair": _couch(b, size, c, a, 1)
		"table": _table(b, size, c)
		"desk": _table(b, size, c)
		"chair": _chair(b, size, c, a)
		"chair_wrong": _chair_wrong(b, size, c, a)
		"stool": _stool(b, size, c)
		"bench": _bench(b, size, c)
		"cabinet": _cabinet(b, size, c, a)
		"dresser": _dresser(b, size, c, a)
		"wardrobe": _wardrobe(b, size, c, a)
		"bookshelf": _bookshelf(b, size, c, a, item)
		"fridge": _fridge(b, size, c, a)
		"freezer": _freezer(b, size, c, a)
		"washer": _washer(b, size, c, a)
		"tv": _tv(b, size, c, a)
		"lamp_table": _lamp(b, size, c, a, false)
		"lamp_floor": _lamp(b, size, c, a, true)
		"mattress": _mattress(b, size, c, a)
		"bed": _bed(b, size, c, a)
		"piano": _piano(b, size, c, a)
		"piano_grand": _piano_grand(b, size, c, a)
		"mirror": _mirror(b, size, c, a)
		"painting": _painting(b, size, c, a)
		"vase": _vase(b, size, c, a)
		"books": _books(b, size, c, a)
		"radio": _radio(b, size, c, a)
		"plant": _plant(b, size, c, a)
		"clock": _clock(b, size, c, a)
		"toy": _toy(b, size, c, a)
		"crate": _crate(b, size, c, a)
		"suitcase": _suitcase(b, size, c, a)
		"gramophone": _gramophone(b, size, c, a)
		"doll", "doll_large": _doll(b, size, c, a)
		"container": _container(b, size, c, a)
		"sofa_living": _sofa_living(b, size, c, a)
		"bathtub": _bathtub(b, size, c, a)
		"toilet": _toilet(b, size, c, a)
		"stove": _stove(b, size, c, a)
		"counter": _counter(b, size, c, a)
		"cart": _cart(b, size, c, a)
		_: _crate(b, size, c, a)
	return b


# ------------------------------------------------------------- furniture ----

static func _couch(b: MeshBuilder, s: Vector3, c: Color, a: Color, seats: int) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var leg := s.y * 0.09
	b.box(Vector3(s.x, s.y * 0.34, s.z), Vector3(0, leg + s.y * 0.17, 0), c)
	b.box(Vector3(s.x, s.y * 0.62, s.z * 0.2), Vector3(0, leg + s.y * 0.34 + s.y * 0.31, -hz + s.z * 0.1), c.darkened(0.12))
	b.box(Vector3(s.x * 0.09, s.y * 0.44, s.z), Vector3(-hx + s.x * 0.045, leg + s.y * 0.34 + s.y * 0.12, 0), c.darkened(0.06))
	b.box(Vector3(s.x * 0.09, s.y * 0.44, s.z), Vector3(hx - s.x * 0.045, leg + s.y * 0.34 + s.y * 0.12, 0), c.darkened(0.06))
	var usable := s.x - s.x * 0.18
	var per := usable / float(seats)
	for i in seats:
		var x := -usable * 0.5 + per * (i + 0.5)
		b.box(Vector3(per * 0.92, s.y * 0.13, s.z * 0.72), Vector3(x, leg + s.y * 0.34 + s.y * 0.065, s.z * 0.05), a)
	# legs
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x * 0.06, leg, s.z * 0.06),
				Vector3(sx * (hx - s.x * 0.08), leg * 0.5, sz * (hz - s.z * 0.1)), a.darkened(0.35), MeshBuilder.Mat.PLAIN, false)


static func _table(b: MeshBuilder, s: Vector3, c: Color) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.09, s.z), Vector3(0, s.y - s.y * 0.045, 0), c)
	b.box(Vector3(s.x * 0.9, s.y * 0.06, s.z * 0.8), Vector3(0, s.y * 0.85, 0), c.darkened(0.25))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x * 0.06, s.y * 0.85, s.z * 0.07),
				Vector3(sx * (hx - s.x * 0.09), s.y * 0.425, sz * (hz - s.z * 0.1)), c.darkened(0.15))


static func _chair(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.07, s.z), Vector3(0, s.y * 0.45, 0), c)
	b.box(Vector3(s.x, s.y * 0.46, s.z * 0.09), Vector3(0, s.y * 0.72, -hz + s.z * 0.06), c)
	b.box(Vector3(s.x * 0.85, s.y * 0.12, s.z * 0.7), Vector3(0, s.y * 0.52, s.z * 0.05), a)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x * 0.08, s.y * 0.44, s.z * 0.08),
				Vector3(sx * (s.x * 0.5 - s.x * 0.07), s.y * 0.22, sz * (hz - s.z * 0.08)), c.darkened(0.2))


static func _chair_wrong(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	_chair(b, s, c, a)
	# teeth under the seat -- visible only when the chair is lifted
	for i in 5:
		var x := -s.x * 0.3 + s.x * 0.15 * i
		b.box(Vector3(s.x * 0.06, s.y * 0.05, s.z * 0.04), Vector3(x, s.y * 0.36, s.z * 0.42), Color(0.93, 0.9, 0.82))
	b.box(Vector3(s.x * 0.8, s.y * 0.02, s.z * 0.03), Vector3(0, s.y * 0.33, s.z * 0.34), Color(0.5, 0.12, 0.12))


static func _stool(b: MeshBuilder, s: Vector3, c: Color) -> void:
	b.cyl(s.x * 0.5, s.x * 0.5, s.y * 0.1, Vector3(0, s.y * 0.95, 0), c, MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 12)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var px := cos(ang) * s.x * 0.34
		var pz := sin(ang) * s.z * 0.34
		b.box(Vector3(s.x * 0.07, s.y * 0.9, s.z * 0.07), Vector3(px, s.y * 0.45, pz), c.darkened(0.18))


static func _bench(b: MeshBuilder, s: Vector3, c: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.1, s.z), Vector3(0, s.y * 0.9, 0), c)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(s.x * 0.08, s.y * 0.85, s.z * 0.85), Vector3(sx * (s.x * 0.42), s.y * 0.425, 0), c.darkened(0.2))


static func _cabinet(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.88, s.z), Vector3(0, s.y * 0.06 + s.y * 0.44, 0), c)
	b.box(Vector3(s.x * 0.44, s.y * 0.74, s.z * 0.04), Vector3(-s.x * 0.23, s.y * 0.5, hz - s.z * 0.02), c.lightened(0.05))
	b.box(Vector3(s.x * 0.44, s.y * 0.74, s.z * 0.04), Vector3(s.x * 0.23, s.y * 0.5, hz - s.z * 0.02), c.lightened(0.05))
	b.box(Vector3(s.x * 0.05, s.y * 0.05, s.z * 0.05), Vector3(-s.x * 0.05, s.y * 0.5, hz + s.z * 0.01), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.05, s.y * 0.05, s.z * 0.05), Vector3(s.x * 0.05, s.y * 0.5, hz + s.z * 0.01), a, MeshBuilder.Mat.METAL)


static func _dresser(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.94, s.z), Vector3(0, s.y * 0.47, 0), c)
	for i in 3:
		var y := s.y * (0.2 + 0.27 * float(i))
		b.box(Vector3(s.x * 0.9, s.y * 0.22, s.z * 0.05), Vector3(0, y, hz - s.z * 0.02), c.lightened(0.06))
		b.box(Vector3(s.x * 0.16, s.y * 0.03, s.z * 0.04), Vector3(0, y, hz + s.z * 0.01), a, MeshBuilder.Mat.METAL)


static func _wardrobe(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.95, s.z), Vector3(0, s.y * 0.475, 0), c)
	b.box(Vector3(s.x * 1.04, s.y * 0.04, s.z * 1.06), Vector3(0, s.y * 0.97, 0), c.darkened(0.15))
	b.box(Vector3(s.x * 0.47, s.y * 0.88, s.z * 0.04), Vector3(-s.x * 0.245, s.y * 0.46, hz - s.z * 0.02), c.lightened(0.04))
	b.box(Vector3(s.x * 0.47, s.y * 0.88, s.z * 0.04), Vector3(s.x * 0.245, s.y * 0.46, hz - s.z * 0.02), c.lightened(0.04))
	b.box(Vector3(s.x * 0.04, s.y * 0.09, s.z * 0.05), Vector3(-s.x * 0.04, s.y * 0.5, hz + s.z * 0.01), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.04, s.y * 0.09, s.z * 0.05), Vector3(s.x * 0.04, s.y * 0.5, hz + s.z * 0.01), a, MeshBuilder.Mat.METAL)


static func _bookshelf(b: MeshBuilder, s: Vector3, c: Color, a: Color, item: Dictionary) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y, s.z * 0.1), Vector3(0, s.y * 0.5, -hz + s.z * 0.05), c.darkened(0.25))
	b.box(Vector3(s.x * 0.07, s.y, s.z), Vector3(-s.x * 0.5 + s.x * 0.035, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.07, s.y, s.z), Vector3(s.x * 0.5 - s.x * 0.035, s.y * 0.5, 0), c)
	b.box(Vector3(s.x, s.y * 0.05, s.z), Vector3(0, s.y * 0.975, 0), c)
	b.box(Vector3(s.x, s.y * 0.05, s.z), Vector3(0, s.y * 0.025, 0), c)
	var shelf_count := 3
	for i in shelf_count:
		var y := s.y * (0.28 + 0.23 * float(i))
		b.box(Vector3(s.x * 0.92, s.y * 0.03, s.z * 0.9), Vector3(0, y, 0), c.darkened(0.1))
		# books
		var rng := U.rng_for(hash(item.get("id", "bookshelf")) + i)
		var x := -s.x * 0.4
		while x < s.x * 0.38:
			var bw := rng.randf_range(0.03, 0.07)
			var bh := rng.randf_range(s.y * 0.12, s.y * 0.19)
			var col := Color.from_hsv(rng.randf(), 0.35, rng.randf_range(0.3, 0.65))
			b.box(Vector3(bw, bh, s.z * 0.6), Vector3(x, y + s.y * 0.015 + bh * 0.5, s.z * 0.05), col)
			x += bw + 0.005
	if s.y > 1.5:
		b.box(Vector3(s.x, s.y * 0.04, s.z), Vector3(0, s.y * 0.5, 0), c.darkened(0.05))  # mid brace


static func _fridge(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(s - Vector3(0.02, 0.04, 0.02), Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.96, s.y * 0.58, s.z * 0.05), Vector3(0, s.y * 0.68, hz - s.z * 0.02), c.darkened(0.06))
	b.box(Vector3(s.x * 0.96, s.y * 0.34, s.z * 0.05), Vector3(0, s.y * 0.17, hz - s.z * 0.02), c.darkened(0.03))
	b.box(Vector3(s.x * 0.06, s.y * 0.3, s.z * 0.06), Vector3(s.x * 0.4, s.y * 0.66, hz + s.z * 0.02), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.06, s.y * 0.14, s.z * 0.06), Vector3(s.x * 0.4, s.y * 0.22, hz + s.z * 0.02), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.9, s.y * 0.03, s.z * 0.9), Vector3(0, 0.015, 0), a.darkened(0.3), MeshBuilder.Mat.METAL)


static func _freezer(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 1.02, s.y * 0.06, s.z * 1.02), Vector3(0, s.y * 0.95, 0), c.lightened(0.05))
	b.box(Vector3(s.x * 0.3, s.y * 0.05, s.z * 0.06), Vector3(0, s.y * 0.86, s.z * 0.5), a, MeshBuilder.Mat.METAL)


static func _washer(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	b.cyl(minf(s.x, s.y) * 0.3, minf(s.x, s.y) * 0.3, s.z * 0.05, Vector3(0, s.y * 0.5, hz),
		a, MeshBuilder.Mat.GLASS, false, Vector3(PI * 0.5, 0, 0), 14)
	b.box(Vector3(s.x * 0.9, s.y * 0.12, s.z * 0.05), Vector3(0, s.y * 0.92, hz - s.z * 0.01), a.darkened(0.3))
	b.cyl(s.x * 0.03, s.x * 0.03, s.y * 0.04, Vector3(-s.x * 0.3, s.y * 0.92, hz + s.z * 0.01), Color(0.9, 0.35, 0.25), MeshBuilder.Mat.EMISSIVE, false, Vector3(PI * 0.5, 0, 0), 8)


static func _tv(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.8, s.z * 0.5), Vector3(0, s.y * 0.62, 0), c)
	b.box(Vector3(s.x * 0.9, s.y * 0.66, s.z * 0.2), Vector3(0, s.y * 0.62, s.z * 0.12), a.darkened(0.55), MeshBuilder.Mat.GLASS)
	b.box(Vector3(s.x * 0.16, s.y * 0.22, s.z * 0.3), Vector3(0, s.y * 0.11, s.z * 0.1), c.darkened(0.4))
	b.box(Vector3(s.x * 0.5, s.y * 0.04, s.z * 0.6), Vector3(0, s.y * 0.02, s.z * 0.1), c.darkened(0.5))


static func _lamp(b: MeshBuilder, s: Vector3, c: Color, a: Color, tall: bool) -> void:
	var base_h := s.y * (0.05 if tall else 0.12)
	b.cyl(s.x * (0.42 if not tall else 0.5), s.x * (0.46 if not tall else 0.55), base_h, Vector3(0, base_h * 0.5, 0), c, MeshBuilder.Mat.METAL, true, Vector3.ZERO, 12)
	var pole_top := s.y * (0.82 if tall else 0.66)
	b.cyl(s.x * 0.035, s.x * 0.045, pole_top, Vector3(0, base_h + pole_top * 0.5, 0), c.darkened(0.2), MeshBuilder.Mat.METAL, false, Vector3.ZERO, 8)
	var shade_h := s.y * (0.2 if tall else 0.28)
	b.cyl(s.x * 0.3, s.x * 0.52, shade_h, Vector3(0, s.y - shade_h * 0.5, 0), a, MeshBuilder.Mat.EMISSIVE, false, Vector3.ZERO, 12)


static func _mattress(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.9, s.y * 0.5, s.z * 0.9), Vector3(0, s.y * 0.25, 0), c.darkened(0.1))
	b.box(Vector3(s.x * 0.32, s.y * 0.9, s.z * 0.16), Vector3(-s.x * 0.22, s.y * 1.0, -s.z * 0.36), a)
	b.box(Vector3(s.x * 0.32, s.y * 0.9, s.z * 0.16), Vector3(s.x * 0.22, s.y * 1.0, -s.z * 0.36), a)


static func _bed(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.3, s.z), Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x, s.y * 0.9, s.z * 0.08), Vector3(0, s.y * 0.62, -s.z * 0.5 + s.z * 0.04), c.darkened(0.15))
	b.box(Vector3(s.x * 0.94, s.y * 0.18, s.z * 0.94), Vector3(0, s.y * 0.72, 0), a)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(s.x * 0.06, s.y * 0.42, s.z * 0.05), Vector3(sx * (s.x * 0.46), s.y * 0.21, sz * (s.z * 0.45)), c.darkened(0.25))


static func _piano(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.62, s.z), Vector3(0, s.y * 0.55, 0), c)
	b.box(Vector3(s.x * 1.02, s.y * 0.07, s.z * 1.02), Vector3(0, s.y * 0.9, 0), c.darkened(0.15))
	b.box(Vector3(s.x * 0.94, s.y * 0.16, s.z * 0.35), Vector3(0, s.y * 0.62, s.z * 0.42), c.lightened(0.08))
	b.box(Vector3(s.x * 0.88, s.y * 0.03, s.z * 0.18), Vector3(0, s.y * 0.7, s.z * 0.42), a)
	# keys
	var keys := 22
	for i in keys:
		var kw := s.x * 0.86 / float(keys)
		b.box(Vector3(kw * 0.85, s.y * 0.015, s.z * 0.13), Vector3(-s.x * 0.43 + kw * (i + 0.5), s.y * 0.715, s.z * 0.45), Color(0.95, 0.94, 0.9))
		if i % 7 != 2 and i % 7 != 6:
			b.box(Vector3(kw * 0.5, s.y * 0.02, s.z * 0.08), Vector3(-s.x * 0.43 + kw * (i + 0.5), s.y * 0.725, s.z * 0.41), Color(0.1, 0.1, 0.1))
	for sx in [-1.0, 1.0]:
		b.box(Vector3(s.x * 0.07, s.y * 0.3, s.z * 0.7), Vector3(sx * s.x * 0.42, s.y * 0.15, 0), c.darkened(0.2))
	b.box(Vector3(s.x * 0.2, s.y * 0.05, s.z * 0.06), Vector3(0, s.y * 0.03, s.z * 0.42), a, MeshBuilder.Mat.METAL)


static func _piano_grand(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.45, s.z * 0.92), Vector3(0, s.y * 0.72, -s.z * 0.04), c)
	var lid := MeshBuilder.new()
	lid.box(Vector3(s.x * 0.98, s.y * 0.05, s.z * 0.9), Vector3(0, 0, 0), c.darkened(0.1))
	b.merge_from(lid, Vector3(0, s.y * 1.02, -s.z * 0.02))
	b.box(Vector3(s.x * 0.94, s.y * 0.1, s.z * 0.3), Vector3(0, s.y * 0.5, s.z * 0.42), c)
	b.box(Vector3(s.x * 0.86, s.y * 0.03, s.z * 0.16), Vector3(0, s.y * 0.56, s.z * 0.44), a)
	for sx in [-1.0, 0.0, 1.0]:
		b.box(Vector3(s.x * 0.07, s.y * 0.5, s.z * 0.07), Vector3(sx * s.x * 0.4, s.y * 0.25, s.z * (0.25 if sx == 0.0 else -0.3)), c.darkened(0.2))


static func _mirror(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.06, s.z), Vector3(0, s.y * 0.97, 0), c)
	b.box(Vector3(s.x, s.y * 0.06, s.z), Vector3(0, s.y * 0.03, 0), c)
	b.box(Vector3(s.x * 0.06, s.y, s.z), Vector3(-s.x * 0.47, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.06, s.y, s.z), Vector3(s.x * 0.47, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.9, s.y * 0.9, s.z * 0.3), Vector3(0, s.y * 0.5, 0), a, MeshBuilder.Mat.GLASS)
	b.box(Vector3(s.x * 0.7, s.y * 0.08, s.z * 0.9), Vector3(0, s.y * 0.02, 0), c.darkened(0.3))


static func _painting(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.08, s.z), Vector3(0, s.y * 0.96, 0), c)
	b.box(Vector3(s.x, s.y * 0.08, s.z), Vector3(0, s.y * 0.04, 0), c)
	b.box(Vector3(s.x * 0.07, s.y, s.z), Vector3(-s.x * 0.465, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.07, s.y, s.z), Vector3(s.x * 0.465, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.86, s.y * 0.84, s.z * 0.4), Vector3(0, s.y * 0.5, 0), a)
	# abstract composition
	b.box(Vector3(s.x * 0.3, s.y * 0.2, s.z * 0.2), Vector3(-s.x * 0.16, s.y * 0.38, hz * 0.3), Color(0.2, 0.18, 0.22))
	b.cyl(s.x * 0.14, s.x * 0.14, s.z * 0.2, Vector3(s.x * 0.2, s.y * 0.6, hz * 0.3), Color(0.65, 0.55, 0.3), MeshBuilder.Mat.PLAIN, false, Vector3(PI * 0.5, 0, 0), 10)


static func _vase(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.cyl(s.x * 0.3, s.x * 0.42, s.y * 0.6, Vector3(0, s.y * 0.3, 0), c, MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 14)
	b.cyl(s.x * 0.16, s.x * 0.3, s.y * 0.28, Vector3(0, s.y * 0.74, 0), c, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 14)
	b.cyl(s.x * 0.19, s.x * 0.17, s.y * 0.08, Vector3(0, s.y * 0.92, 0), a, MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 14)


static func _books(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var y := 0.0
	var rng := U.rng_for(hash(c.to_html()))
	for i in 4:
		var h := s.y * rng.randf_range(0.16, 0.26)
		var col := Color.from_hsv(rng.randf(), 0.4, rng.randf_range(0.25, 0.6))
		b.box(Vector3(s.x * rng.randf_range(0.8, 1.0), h, s.z * rng.randf_range(0.8, 1.0)),
			Vector3(rng.randf_range(-0.02, 0.02), y + h * 0.5, rng.randf_range(-0.02, 0.02)), col, MeshBuilder.Mat.PLAIN, true,
			Vector3(0, rng.randf_range(-0.15, 0.15), 0))
		y += h


static func _radio(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.5, s.y * 0.6, s.z * 0.1), Vector3(-s.x * 0.2, s.y * 0.5, hz), a.darkened(0.5))
	b.cyl(s.x * 0.09, s.x * 0.09, s.z * 0.1, Vector3(s.x * 0.3, s.y * 0.55, hz), Color(0.9, 0.85, 0.6), MeshBuilder.Mat.EMISSIVE, false, Vector3(PI * 0.5, 0, 0), 10)
	b.cyl(0.004, 0.006, s.y * 1.2, Vector3(s.x * 0.3, s.y * 1.4, -hz * 0.4), a, MeshBuilder.Mat.METAL, false, Vector3(0, 0, 0.2), 6)


static func _plant(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.cyl(s.x * 0.4, s.x * 0.46, s.y * 0.35, Vector3(0, s.y * 0.175, 0), c, MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 12)
	b.cyl(s.x * 0.37, s.x * 0.37, 0.02, Vector3(0, s.y * 0.34, 0), Color(0.18, 0.14, 0.1))
	var rng := U.rng_for(42)
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var lean := rng.randf_range(0.2, 0.55)
		var h := s.y * rng.randf_range(0.35, 0.6)
		b.sphere(s.x * 0.16, Vector3(cos(ang) * lean * s.x * 0.8, s.y * 0.35 + h * 0.7, sin(ang) * lean * s.x * 0.8),
			a.darkened(rng.randf_range(0.0, 0.3)), MeshBuilder.Mat.PLAIN, false, h * 0.9)


static func _clock(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.98, s.z), Vector3(0, s.y * 0.49, 0), c)
	b.box(Vector3(s.x * 1.08, s.y * 0.04, s.z * 1.1), Vector3(0, s.y * 0.98, 0), c.darkened(0.2))
	b.cyl(s.x * 0.3, s.x * 0.3, s.z * 0.06, Vector3(0, s.y * 0.8, hz - s.z * 0.02), a, MeshBuilder.Mat.EMISSIVE, false, Vector3(PI * 0.5, 0, 0), 16)
	b.box(Vector3(s.x * 0.5, s.y * 0.35, s.z * 0.5), Vector3(0, s.y * 0.3, 0), c.darkened(0.35))
	b.box(Vector3(s.x * 0.06, s.y * 0.22, s.z * 0.05), Vector3(0, s.y * 0.32, hz * 0.52), a, MeshBuilder.Mat.METAL)


static func _toy(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.sphere(s.x * 0.45, Vector3(0, s.y * 0.32, 0), c, MeshBuilder.Mat.PLAIN, true, s.y * 0.6)
	b.sphere(s.x * 0.34, Vector3(0, s.y * 0.72, 0), c.lightened(0.05), MeshBuilder.Mat.PLAIN, false, s.y * 0.45)
	b.sphere(s.x * 0.12, Vector3(-s.x * 0.26, s.y * 0.9, 0), c.darkened(0.1))
	b.sphere(s.x * 0.12, Vector3(s.x * 0.26, s.y * 0.9, 0), c.darkened(0.1))
	b.sphere(s.x * 0.06, Vector3(-s.x * 0.13, s.y * 0.76, s.z * 0.3), Color(0.06, 0.05, 0.05))
	b.sphere(s.x * 0.06, Vector3(s.x * 0.13, s.y * 0.76, s.z * 0.3), Color(0.06, 0.05, 0.05))
	b.sphere(s.x * 0.07, Vector3(0, s.y * 0.68, s.z * 0.32), a)


static func _crate(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y, s.z), Vector3(0, s.y * 0.5, 0), c)
	var t := 0.05
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(Vector3(t * s.x, s.y, t * s.z), Vector3(sx * (s.x * 0.5 - t * s.x * 0.5), s.y * 0.5, sz * (s.z * 0.5 - t * s.z * 0.5)), a.darkened(0.1))
	b.box(Vector3(s.x * 1.01, s.y * 0.06, s.z * 1.01), Vector3(0, s.y * 0.9, 0), a.darkened(0.2))
	b.box(Vector3(s.x * 1.01, s.y * 0.06, s.z * 1.01), Vector3(0, s.y * 0.12, 0), a.darkened(0.2))


static func _suitcase(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	b.box(Vector3(s.x * 0.3, s.y * 0.06, s.z * 0.2), Vector3(0, s.y * 0.99, 0), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.9, s.y * 0.02, s.z * 1.02), Vector3(0, s.y * 0.5, 0), a.darkened(0.3))
	b.box(Vector3(s.x * 0.1, s.y * 0.08, s.z * 0.2), Vector3(-s.x * 0.3, s.y * 0.55, 0), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.1, s.y * 0.08, s.z * 0.2), Vector3(s.x * 0.3, s.y * 0.55, 0), a, MeshBuilder.Mat.METAL)


static func _gramophone(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.3, s.z), Vector3(0, s.y * 0.15, 0), c)
	b.cyl(s.x * 0.09, s.x * 0.42, s.y * 0.4, Vector3(0, s.y * 0.55, 0), a, MeshBuilder.Mat.METAL, false, Vector3(0, 0, 0.25), 14)
	b.cyl(s.x * 0.3, s.x * 0.3, 0.02, Vector3(0, s.y * 0.32, 0), Color(0.08, 0.07, 0.06), MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 14)
	b.box(Vector3(s.x * 0.06, s.y * 0.05, s.z * 0.5), Vector3(s.x * 0.2, s.y * 0.36, 0), a, MeshBuilder.Mat.METAL, false, Vector3(0, 0.4, 0))


static func _doll(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.cyl(s.x * 0.18, s.x * 0.5, s.y * 0.5, Vector3(0, s.y * 0.25, 0), a, MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 12)
	b.sphere(s.x * 0.3, Vector3(0, s.y * 0.62, 0), c, MeshBuilder.Mat.PLAIN, false, s.y * 0.3)
	b.sphere(s.x * 0.28, Vector3(0, s.y * 0.85, 0), c.lightened(0.05), MeshBuilder.Mat.PLAIN, true, s.y * 0.26)
	b.sphere(s.x * 0.05, Vector3(-s.x * 0.11, s.y * 0.87, s.z * 0.24), Color(0.05, 0.05, 0.06))
	b.sphere(s.x * 0.05, Vector3(s.x * 0.11, s.y * 0.87, s.z * 0.24), Color(0.05, 0.05, 0.06))
	b.sphere(s.x * 0.22, Vector3(0, s.y * 0.99, 0), a.darkened(0.2), MeshBuilder.Mat.PLAIN, false, s.y * 0.08)
	b.box(Vector3(s.x * 0.08, s.y * 0.28, s.z * 0.08), Vector3(-s.x * 0.32, s.y * 0.62, 0), c, MeshBuilder.Mat.PLAIN, false, Vector3(0, 0, 0.3))
	b.box(Vector3(s.x * 0.08, s.y * 0.28, s.z * 0.08), Vector3(s.x * 0.32, s.y * 0.62, 0), c, MeshBuilder.Mat.PLAIN, false, Vector3(0, 0, -0.3))


static func _container(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y, s.z), Vector3(0, s.y * 0.5, 0), c, MeshBuilder.Mat.PLAIN, true)
	for i in 2:
		b.box(Vector3(s.x * 1.02, s.y * 0.05, s.z * 1.02), Vector3(0, s.y * (0.25 + 0.5 * i), 0), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.16, s.y * 0.16, s.z * 0.06), Vector3(0, s.y * 0.5, s.z * 0.5), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.08, s.y * 0.1, s.z * 0.03), Vector3(0, s.y * 0.5, s.z * 0.53), Color(0.9, 0.3, 0.2), MeshBuilder.Mat.EMISSIVE, false)


static func _sofa_living(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	_couch(b, s, c, a, 3)
	# eyes and a mouth on the back rest -- the object is awake
	var hz := s.z * 0.5
	var eye_y := s.y * 0.34 + s.y * 0.31 + s.y * 0.16
	b.sphere(s.x * 0.055, Vector3(-s.x * 0.16, eye_y, -hz + s.z * 0.1), Color(0.95, 0.85, 0.5), MeshBuilder.Mat.EMISSIVE, false)
	b.sphere(s.x * 0.055, Vector3(s.x * 0.16, eye_y, -hz + s.z * 0.1), Color(0.95, 0.85, 0.5), MeshBuilder.Mat.EMISSIVE, false)
	b.box(Vector3(s.x * 0.34, s.y * 0.03, s.z * 0.02), Vector3(0, eye_y - s.y * 0.14, -hz + s.z * 0.1), Color(0.25, 0.06, 0.07))


static func _bathtub(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var t := 0.06
	b.box(Vector3(s.x, t * s.y, s.z), Vector3(0, t * s.y * 0.5, 0), a)
	b.box(Vector3(s.x, s.y, t * s.z * 2.0), Vector3(0, s.y * 0.5, -s.z * 0.5 + t * s.z), c)
	b.box(Vector3(s.x, s.y, t * s.z * 2.0), Vector3(0, s.y * 0.5, s.z * 0.5 - t * s.z), c)
	b.box(Vector3(t * s.x * 2.0, s.y, s.z), Vector3(-s.x * 0.5 + t * s.x, s.y * 0.5, 0), c)
	b.box(Vector3(t * s.x * 2.0, s.y, s.z), Vector3(s.x * 0.5 - t * s.x, s.y * 0.5, 0), c)
	b.cyl(0.03, 0.03, s.y * 0.5, Vector3(-s.x * 0.4, s.y * 0.75, 0), a, MeshBuilder.Mat.METAL)


static func _toilet(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.cyl(s.x * 0.42, s.x * 0.34, s.y * 0.4, Vector3(0, s.y * 0.2, s.z * 0.1), c, MeshBuilder.Mat.PLAIN, true, Vector3.ZERO, 14)
	b.cyl(s.x * 0.5, s.x * 0.5, s.y * 0.06, Vector3(0, s.y * 0.44, s.z * 0.1), c.lightened(0.05), MeshBuilder.Mat.PLAIN, false, Vector3.ZERO, 14)
	b.box(Vector3(s.x * 0.9, s.y * 0.42, s.z * 0.36), Vector3(0, s.y * 0.65, -s.z * 0.28), c)
	b.box(Vector3(s.x * 0.9, s.y * 0.05, s.z * 0.4), Vector3(0, s.y * 0.88, -s.z * 0.28), a)


static func _stove(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(s, Vector3(0, s.y * 0.5, 0), c)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.cyl(s.x * 0.19, s.x * 0.19, 0.02, Vector3(sx * s.x * 0.24, s.y, sz * s.z * 0.24), a, MeshBuilder.Mat.METAL, false, Vector3.ZERO, 14)
	b.box(Vector3(s.x * 0.8, s.y * 0.4, s.z * 0.05), Vector3(0, s.y * 0.35, hz - s.z * 0.02), a.darkened(0.5), MeshBuilder.Mat.GLASS)
	b.box(Vector3(s.x * 0.8, s.y * 0.04, s.z * 0.06), Vector3(0, s.y * 0.58, hz), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x * 0.9, s.y * 0.1, s.z * 0.06), Vector3(0, s.y * 0.88, hz - s.z * 0.01), a)


static func _counter(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	var hz := s.z * 0.5
	b.box(Vector3(s.x, s.y * 0.86, s.z), Vector3(0, s.y * 0.45, 0), c)
	b.box(Vector3(s.x * 1.02, s.y * 0.07, s.z * 1.04), Vector3(0, s.y * 0.93, 0), a)
	b.box(Vector3(s.x * 0.9, s.y * 0.6, s.z * 0.04), Vector3(0, s.y * 0.42, hz - s.z * 0.02), c.lightened(0.06))
	b.cyl(s.x * 0.06, s.x * 0.06, s.y * 0.18, Vector3(0, s.y * 0.7, -s.z * 0.2), a, MeshBuilder.Mat.METAL, false, Vector3.ZERO, 10)


static func _cart(b: MeshBuilder, s: Vector3, c: Color, a: Color) -> void:
	b.box(Vector3(s.x, s.y * 0.06, s.z), Vector3(0, s.y * 0.22, 0), c)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(s.x * 0.06, s.y * 0.7, s.z * 0.06), Vector3(sx * s.x * 0.45, s.y * 0.55, -s.z * 0.45), a, MeshBuilder.Mat.METAL)
	b.box(Vector3(s.x, s.y * 0.05, s.z * 0.05), Vector3(0, s.y * 0.9, -s.z * 0.45), a, MeshBuilder.Mat.METAL)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.cyl(s.y * 0.1, s.y * 0.1, s.x * 0.08, Vector3(sx * s.x * 0.48, s.y * 0.1, sz * s.z * 0.38),
				Color(0.12, 0.12, 0.13), MeshBuilder.Mat.METAL, false, Vector3(0, 0, PI * 0.5), 12)


# ---------------------------------------------------------------- helpers ---

## Convenience for level geometry: a wall segment with a rectangular opening.
static func wall_with_opening(b: MeshBuilder, from: Vector3, to: Vector3, height: float, thickness: float,
		opening_center: float, opening_width: float, opening_height: float, color: Color) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return
	var along := dir / length
	var yaw := atan2(-along.z, along.x)
	var mid := (from + to) * 0.5
	if opening_width <= 0.01:
		b.box(Vector3(length, height, thickness), Vector3(mid.x, height * 0.5, mid.z), color, MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))
		return
	var left_len := opening_center - opening_width * 0.5
	var right_len := length - (opening_center + opening_width * 0.5)
	if left_len > 0.01:
		var c1 := from + along * (left_len * 0.5)
		b.box(Vector3(left_len, height, thickness), Vector3(c1.x, height * 0.5, c1.z), color, MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))
	if right_len > 0.01:
		var c2 := from + along * (opening_center + opening_width * 0.5 + right_len * 0.5)
		b.box(Vector3(right_len, height, thickness), Vector3(c2.x, height * 0.5, c2.z), color, MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))
	var lintel_h := height - opening_height
	if lintel_h > 0.01:
		var c3 := from + along * opening_center
		b.box(Vector3(opening_width, lintel_h, thickness), Vector3(c3.x, opening_height + lintel_h * 0.5, c3.z), color, MeshBuilder.Mat.PLAIN, true, Vector3(0, yaw, 0))
