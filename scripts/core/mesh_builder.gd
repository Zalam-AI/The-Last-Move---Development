class_name MeshBuilder
extends RefCounted
## Accumulates simple primitives and commits them as ONE merged mesh plus box/cylinder
## collision shapes. Used for both furniture (dynamic) and architecture (static) so the
## whole game renders with a handful of draw calls per object instead of per-part.

enum Mat { PLAIN, METAL, GLASS, EMISSIVE }

var parts: Array[Dictionary] = []


func box(size: Vector3, pos: Vector3, color: Color, mat := Mat.PLAIN, collide := true, rot := Vector3.ZERO) -> MeshBuilder:
	parts.append({
		"kind": "box", "size": size, "pos": pos, "color": color,
		"mat": mat, "collide": collide, "rot": rot,
	})
	return self


func cyl(top_r: float, bottom_r: float, height: float, pos: Vector3, color: Color,
		mat := Mat.PLAIN, collide := false, rot := Vector3.ZERO, sides := 12) -> MeshBuilder:
	parts.append({
		"kind": "cyl", "top_r": top_r, "bottom_r": bottom_r, "height": height,
		"pos": pos, "color": color, "mat": mat, "collide": collide, "rot": rot, "sides": sides,
	})
	return self


func sphere(radius: float, pos: Vector3, color: Color, mat := Mat.PLAIN, collide := false, height := -1.0) -> MeshBuilder:
	parts.append({
		"kind": "sphere", "radius": radius, "pos": pos, "color": color,
		"mat": mat, "collide": collide, "height": height if height > 0.0 else radius * 2.0,
	})
	return self


func merge_from(other: MeshBuilder, offset := Vector3.ZERO) -> MeshBuilder:
	for p in other.parts:
		var c: Dictionary = p.duplicate()
		c["pos"] = c["pos"] + offset
		parts.append(c)
	return self


## Builds the merged ArrayMesh (one surface per material group).
func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var groups := {}
	for i in parts.size():
		var m: int = parts[i]["mat"]
		if not groups.has(m):
			groups[m] = []
		groups[m].append(parts[i])
	var keys := [Mat.PLAIN, Mat.METAL, Mat.GLASS, Mat.EMISSIVE]
	for key in keys:
		if not groups.has(key) or groups[key].is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in groups[key]:
			_append_primitive(st, p)
		var surf := st.commit_to_arrays()
		var idx := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf)
		mesh.surface_set_material(idx, AssetLib.material_for(key))
	return mesh


func _append_primitive(st: SurfaceTool, p: Dictionary) -> void:
	var src: PrimitiveMesh
	match p["kind"]:
		"box":
			var b := BoxMesh.new()
			b.size = p["size"]
			src = b
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = p["top_r"]
			c.bottom_radius = p["bottom_r"]
			c.height = p["height"]
			c.radial_segments = int(p.get("sides", 12))
			c.rings = 1
			src = c
		"sphere":
			var s := SphereMesh.new()
			s.radius = p["radius"]
			s.height = p["height"]
			s.radial_segments = 12
			s.rings = 6
			src = s
	var xf := Transform3D(Basis.from_euler(p.get("rot", Vector3.ZERO)), p["pos"])
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var col: Color = p["color"]
	var basis := xf.basis
	for i in indices.size():
		var vi := indices[i]
		st.set_color(col)
		st.set_normal((basis * norms[vi]).normalized())
		st.add_vertex(xf * verts[vi])


## Commits a MeshInstance3D (+ optional StaticBody3D collision) under `parent`.
func commit_static(parent: Node3D, node_name := "Geometry", collide := true) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = build_mesh()
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		for p in parts:
			if not p.get("collide", false):
				continue
			var shape := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = p["size"] if p["kind"] == "box" else _approx_size(p)
			shape.shape = box_shape
			shape.position = p["pos"]
			shape.rotation = p.get("rot", Vector3.ZERO)
			body.add_child(shape)
		root.add_child(body)
	parent.add_child(root)
	return root


func _approx_size(p: Dictionary) -> Vector3:
	if p["kind"] == "sphere":
		var d := float(p["radius"]) * 2.0
		return Vector3(d, float(p.get("height", d)), d)
	var d2 := maxf(p["top_r"], p["bottom_r"]) * 2.0
	return Vector3(d2, p["height"], d2)


## Creates collision-only shapes for a dynamic body from the collidable parts.
func make_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for p in parts:
		if not p.get("collide", false):
			continue
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p["size"] if p["kind"] == "box" else _approx_size(p)
		cs.shape = bs
		cs.position = p["pos"]
		cs.rotation = p.get("rot", Vector3.ZERO)
		out.append(cs)
	return out
