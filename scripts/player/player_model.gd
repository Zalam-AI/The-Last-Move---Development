class_name PlayerModel
extends Node3D
## Procedural third-person body for other players ("the crew you can see").
## Built from primitives with separately animatable limbs, so we get readable walking,
## carrying, crouching and falling poses without any imported animation data.

var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hat: Node3D
var _phase := 0.0
var _carry_w := 0.0
var _crouch_w := 0.0
var _lean := 0.0
var _uniform := Color("#2f4f6b")


func setup(equipped: Dictionary) -> void:
	var uni_col := Save.cosmetic_color("uniform", Color("#2f4f6b"))
	var skin := Color("#c89a78")
	var glove := Save.cosmetic_color("gloves", Color("#4a4a52"))
	var boot := Save.cosmetic_color("boots", Color("#2b2622"))
	if equipped.is_empty():
		uni_col = Save.cosmetic_color("uniform", Color("#2f4f6b"))
	_uniform = uni_col

	torso = _limb("Torso", Vector3(0, 0.62, 0), Color(0, 0, 0, 0))
	var b := MeshBuilder.new()
	b.box(Vector3(0.46, 0.6, 0.26), Vector3.ZERO, uni_col)
	b.box(Vector3(0.48, 0.1, 0.28), Vector3(0, -0.28, 0), uni_col.darkened(0.25))  # belt
	b.box(Vector3(0.1, 0.08, 0.06), Vector3(0.16, -0.3, 0.14), Color("#c8a24a"), MeshBuilder.Mat.METAL)  # belt buckle
	torso.add_child(_mesh_from(b))
	head = _limb("Head", Vector3(0, 1.14, 0), Color(0, 0, 0, 0))
	var hb := MeshBuilder.new()
	hb.sphere(0.145, Vector3.ZERO, skin, MeshBuilder.Mat.PLAIN, false, 0.3)
	hb.box(Vector3(0.3, 0.05, 0.3), Vector3(0, -0.12, 0), uni_col.darkened(0.2))  # collar
	hb.box(Vector3(0.05, 0.04, 0.05), Vector3(0, 0.06, 0.14), Color(0.15, 0.13, 0.12))  # eyes region
	head.add_child(_mesh_from(hb))
	hat = Node3D.new()
	hat.name = "Hat"
	hat.position = Vector3(0, 0.1, 0)
	head.add_child(hat)

	arm_l = _limb("ArmL", Vector3(-0.28, 0.86, 0), Color(0, 0, 0, 0))
	arm_r = _limb("ArmR", Vector3(0.28, 0.86, 0), Color(0, 0, 0, 0))
	for a in [arm_l, arm_r]:
		var ab := MeshBuilder.new()
		ab.box(Vector3(0.13, 0.5, 0.14), Vector3(0, -0.25, 0), uni_col)
		ab.box(Vector3(0.12, 0.12, 0.13), Vector3(0, -0.55, 0), glove)
		a.add_child(_mesh_from(ab))

	leg_l = _limb("LegL", Vector3(-0.12, 0.6, 0), Color(0, 0, 0, 0))
	leg_r = _limb("LegR", Vector3(0.12, 0.6, 0), Color(0, 0, 0, 0))
	for l in [leg_l, leg_r]:
		var lb := MeshBuilder.new()
		lb.box(Vector3(0.17, 0.56, 0.19), Vector3(0, -0.28, 0), uni_col.darkened(0.15))
		lb.box(Vector3(0.18, 0.14, 0.26), Vector3(0, -0.55, 0.04), boot)
		l.add_child(_mesh_from(lb))

	var hat_id: String = equipped.get("hat", "hat_none")
	if hat_id != "" and hat_id != "hat_none":
		var hc := Save.cosmetic_color("hat", Color("#2f4f6b"))
		var hbb := MeshBuilder.new()
		if hat_id == "hat_hardhat":
			hbb.sphere(0.17, Vector3(0, 0.03, 0), hc, MeshBuilder.Mat.PLAIN, false, 0.18)
			hbb.box(Vector3(0.36, 0.02, 0.3), Vector3(0, -0.04, 0.03), hc.darkened(0.1))
		elif hat_id == "hat_beanie":
			hbb.sphere(0.16, Vector3(0, 0.02, 0), hc, MeshBuilder.Mat.PLAIN, false, 0.2)
		else:
			hbb.sphere(0.16, Vector3(0, 0.05, 0), hc, MeshBuilder.Mat.PLAIN, false, 0.12)
			hbb.box(Vector3(0.3, 0.02, 0.16), Vector3(0, 0.0, 0.14), hc.darkened(0.15))
		hat.add_child(_mesh_from(hbb))


func _limb(node_name: String, pos: Vector3, _c: Color) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	add_child(n)
	return n


func _mesh_from(b: MeshBuilder) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = b.build_mesh()
	return mi


## Called every frame by the owning player node.
func animate(delta: float, horiz_speed: float, crouching: bool, carrying: bool, on_floor: bool, downed: bool) -> void:
	var move_amount := clampf(horiz_speed / 4.0, 0.0, 1.6)
	_phase += delta * (4.0 + horiz_speed * 2.2)
	_carry_w = U.damp(_carry_w, 1.0 if carrying else 0.0, 8.0, delta)
	_crouch_w = U.damp(_crouch_w, 1.0 if crouching else 0.0, 10.0, delta)
	var swing := sin(_phase) * 0.55 * move_amount
	var swing2 := sin(_phase + PI) * 0.55 * move_amount

	if downed:
		# crumpled on the floor
		rotation.x = U.damp(rotation.x, -1.35, 6.0, delta)
		position.y = U.damp(position.y, 0.42, 6.0, delta)
		leg_l.rotation.x = U.damp(leg_l.rotation.x, 1.2, 6.0, delta)
		leg_r.rotation.x = U.damp(leg_r.rotation.x, 0.9, 6.0, delta)
		arm_l.rotation.x = U.damp(arm_l.rotation.x, 2.0, 6.0, delta)
		arm_r.rotation.x = U.damp(arm_r.rotation.x, 1.8, 6.0, delta)
		return

	position.y = U.damp(position.y, -0.32 * _crouch_w, 12.0, delta)
	rotation.x = U.damp(rotation.x, -0.18 * _crouch_w + (0.06 * move_amount if not on_floor else 0.0), 8.0, delta)

	leg_l.rotation.x = U.damp(leg_l.rotation.x, swing - 0.5 * _crouch_w, 14.0, delta)
	leg_r.rotation.x = U.damp(leg_r.rotation.x, swing2 - 0.5 * _crouch_w, 14.0, delta)
	leg_l.rotation.z = U.damp(leg_l.rotation.z, 0.0, 10.0, delta)
	leg_r.rotation.z = U.damp(leg_r.rotation.z, 0.0, 10.0, delta)

	# arms: swing when walking, reach forward when carrying
	var arm_target_l := lerpf(-swing2 * 0.8, -1.35, _carry_w)
	var arm_target_r := lerpf(-swing * 0.8, -1.35, _carry_w)
	arm_l.rotation.x = U.damp(arm_l.rotation.x, arm_target_l, 12.0, delta)
	arm_r.rotation.x = U.damp(arm_r.rotation.x, arm_target_r, 12.0, delta)
	arm_l.rotation.z = U.damp(arm_l.rotation.z, lerpf(0.08, 0.35, _carry_w), 8.0, delta)
	arm_r.rotation.z = U.damp(arm_r.rotation.z, lerpf(-0.08, -0.35, _carry_w), 8.0, delta)
	torso.rotation.z = U.damp(torso.rotation.z, sin(_phase) * 0.05 * move_amount, 10.0, delta)
	head.rotation.x = U.damp(head.rotation.x, -0.12 * _carry_w, 8.0, delta)
	_lean = 0.0
