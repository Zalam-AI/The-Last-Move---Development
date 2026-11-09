class_name Furniture
extends RigidBody3D
## A physical, grabbable piece of furniture.
##
## Networking model
## ----------------
## The HOST simulates every furniture body. Clients freeze the body and chase an
## interpolated transform received in batches from the host (see mission_manager.gd).
## Grab requests travel client -> host as reliable RPCs; the host validates distance and
## grip availability, then broadcasts the authoritative holder list. Forces are applied
## at the players' grip points, so torque (and therefore arguing) emerges naturally.

signal damaged(amount: float, was_destroyed: bool)
signal delivered_state_changed(delivered: bool)
signal picked_up(holder_ids: Array)
signal dropped

const SYNC_HZ := 15.0
const GRIP_BREAK_DIST := 3.2
const DRAG_LIFT_FACTOR := 0.42
const DRAG_MAX_SPEED := 1.15
const MAX_DAMAGE := 1.0

@export var uid: int = 0
@export var item_id: String = "crate"
@export var contract_uid: String = ""
@export var is_required: bool = false
@export var is_optional: bool = false

var data: Dictionary = {}
var size: Vector3 = Vector3.ONE
var weight := 20.0
var base_value := 100
var fragility := 0.3
var material_kind := "wood"
var min_carriers := 1
var grip_count := 2

var damage := 0.0
var delivered := false
var holders: Dictionary = {}          # player_id -> grip_index
var grip_local: Array[Vector3] = []
var is_alive := true
var noise_level := 0.0

var _sync_target_xf := Transform3D.IDENTITY
var _sync_target_lin := Vector3.ZERO
var _sync_has_target := false
var _last_speed := 0.0
var _scrape_timer := 0.0
var _mesh_instance: MeshInstance3D
var _base_color := Color.WHITE
var creature_flag := false
var _impact_cooldown := 0.0
var _lift_accum := 0.0


func _ready() -> void:
	collision_layer = Layers.FURNITURE
	collision_mask = Layers.FURNITURE_MASK
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	sleeping = false
	continuous_cd = true
	linear_damp = 0.6
	angular_damp = 2.2
	body_entered.connect(_on_body_entered)
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not Net.is_host():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## Must be called before adding to the tree (or immediately after) to build the visual.
func setup(p_item_id: String, p_uid: int) -> void:
	item_id = p_item_id
	uid = p_uid
	name = "F%d" % p_uid
	data = DB.get_item(p_item_id)
	size = data.get("size_v", Vector3.ONE)
	weight = float(data.get("weight", 20.0))
	base_value = int(data.get("value", 100))
	fragility = float(data.get("fragility", 0.3))
	material_kind = str(data.get("material", "wood"))
	min_carriers = int(data.get("min_carriers", 1))
	grip_count = int(data.get("grips", 2))
	_base_color = data.get("color_c", Color.GRAY)
	creature_flag = str(data.get("template", "")) in ["sofa_living", "chair_wrong"]
	mass = weight
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, minf(size.y * 0.32, 0.55), 0)
	inertia = Vector3(weight * size.y * size.y / 12.0, weight * size.x * size.x / 12.0, weight * size.z * size.z / 12.0)
	_build_grips()
	_build_visual()


func _build_grips() -> void:
	grip_local.clear()
	var hx := size.x * 0.42
	var hy := clampf(size.y * 0.55, 0.35, 1.15)
	var hz := size.z * 0.45
	match grip_count:
		1:
			grip_local = [Vector3(0, hy, hz * 0.6)]
		2:
			grip_local = [Vector3(-hx, hy, hz * 0.6), Vector3(hx, hy, hz * 0.6)]
		_:
			grip_local = [
				Vector3(-hx, hy, hz * 0.6), Vector3(hx, hy, hz * 0.6),
				Vector3(-hx, hy * 0.55, hz * 0.6), Vector3(hx, hy * 0.55, hz * 0.6),
			]


func _build_visual() -> void:
	var builder := AssetLib.build(data)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = builder.build_mesh()
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	add_child(_mesh_instance)
	for cs in builder.make_shapes():
		add_child(cs)
	# Contract highlight (only visible through walls when the player is close).
	var outline := MeshInstance3D.new()
	outline.name = "Highlight"
	outline.mesh = _mesh_instance.mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.no_depth_test = true
	mat.grow = true
	mat.grow_amount = 0.012
	outline.material_override = mat
	outline.visible = false
	add_child(outline)


func highlight(on: bool) -> void:
	var h := get_node_or_null("Highlight")
	if h:
		h.visible = on


# ------------------------------------------------------------------ carry ---

func can_be_grabbed_by(player_id: int) -> bool:
	if not is_alive or delivered:
		return false
	if holders.has(player_id):
		return false
	if holders.size() >= grip_local.size():
		return false
	if not Net.is_host():
		return false
	return true


func grab(player_id: int) -> bool:
	if not can_be_grabbed_by(player_id):
		return false
	var slot := _next_grip_slot()
	holders[player_id] = slot
	sleeping = false
	freeze = false
	if holders.size() == 1:
		picked_up.emit(holders.keys())
	_rpc_holders()
	return true


func _next_grip_slot() -> int:
	var used := {}
	for k in holders.keys():
		used[int(holders[k])] = true
	for i in grip_local.size():
		if not used.has(i):
			return i
	return 0


func release(player_id: int) -> void:
	if not holders.has(player_id):
		return
	holders.erase(player_id)
	if holders.is_empty():
		dropped.emit()
	_rpc_holders()


func release_all() -> void:
	if holders.is_empty():
		return
	holders.clear()
	dropped.emit()
	_rpc_holders()


@rpc("authority", "call_remote", "reliable")
func _rpc_set_holders(list: Array) -> void:
	holders.clear()
	for i in list.size():
		holders[int(list[i])] = i if list.size() <= grip_local.size() else 0
	if holders.is_empty():
		dropped.emit()
	else:
		picked_up.emit(holders.keys())


func _rpc_holders() -> void:
	if not Net.is_online():
		return
	var ids := []
	for k in holders.keys():
		ids.append(int(k))
	rpc("_rpc_set_holders", ids)


func holder_count() -> int:
	return holders.size()


func is_held() -> bool:
	return not holders.is_empty()


func grip_world(slot: int) -> Vector3:
	return global_transform * grip_local[clampi(slot, 0, grip_local.size() - 1)]


## Where the player's hands should be for a given holder (slightly in front, chest height).
static func hands_for_player(p: Node3D) -> Vector3:
	if p == null:
		return Vector3.ZERO
	var fwd: Vector3 = -p.global_transform.basis.z
	return p.global_position + Vector3.UP * 1.05 + Vector3(fwd.x, 0, fwd.z).normalized() * 0.75


# ------------------------------------------------------------- simulation ---

func _physics_process(delta: float) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or Net.is_host():
		if not freeze:
			_apply_carry_forces(delta)
		_track_motion(delta)
	else:
		_apply_remote_interpolation(delta)


func _apply_carry_forces(delta: float) -> void:
	if holders.is_empty():
		_lift_accum = 0.0
		return
	var strength := Game.crew_strength()
	var target_count := maxi(1, mini(min_carriers, grip_local.size()))
	var under_crewed := holders.size() < target_count
	var lift_factor := 1.0 if not under_crewed else DRAG_LIFT_FACTOR
	var total_error := Vector3.ZERO
	var count := 0
	for pid in holders.keys():
		var p := Game.get_player(int(pid))
		if p == null:
			continue
		var slot: int = int(holders[pid])
		var grip_w := grip_world(slot)
		var hands := hands_for_player(p)
		var err := hands - grip_w
		total_error += err
		count += 1
		if err.length() > GRIP_BREAK_DIST:
			release(int(pid))
			continue
		var point_vel := linear_velocity + angular_velocity.cross(grip_w - global_position)
		var k := 26.0 * strength * lift_factor
		var d := 8.0 * sqrt(strength)
		var force := (err * k - point_vel * d) * mass / float(maxi(1, holders.size()))
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 14.0)
		if under_crewed:
			# An under-crewed lift does not fly: the crew cannot get it off the ground, but
			# they *can* skid it across the floor, which is the whole joke.
			var horiz := Vector3(force.x, 0, force.z)
			var drag_cap := mass * gravity * 0.50 * strength
			if horiz.length() > drag_cap:
				horiz = horiz.normalized() * drag_cap
			force = horiz + Vector3(0, clampf(force.y, -mass * gravity, 0.0), 0)
		else:
			var max_f := mass * 9.0 * strength * lift_factor
			if force.length() > max_f:
				force = force.normalized() * max_f
		apply_force(force, grip_w - global_position)
	# gravity compensation so teamwork doesn't fight the planet
	var comp := mass * float(ProjectSettings.get_setting("physics/3d/default_gravity", 14.0))
	apply_central_force(Vector3.UP * comp * (1.0 if not under_crewed else 0.55) * minf(1.0, strength))
	if under_crewed:
		# A dragged object crawls: one mover can keep it moving, but never at walking pace.
		var flat := Vector3(linear_velocity.x, 0, linear_velocity.z)
		if flat.length() > DRAG_MAX_SPEED:
			var capped := flat.normalized() * DRAG_MAX_SPEED
			linear_velocity = Vector3(capped.x, linear_velocity.y, capped.z)
	# angular stability: stop heavy objects spinning like bottle caps
	apply_torque(-angular_velocity * mass * 0.35 * clampf(size.length() * 0.2, 0.3, 1.4))
	if count > 0:
		_lift_accum += delta


func _track_motion(delta: float) -> void:
	var speed := linear_velocity.length()
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	# scraping noise + wear when dragged along the floor while held
	var on_floor := global_position.y < 0.5 + size.y * 0.55
	if is_held() and on_floor and speed > 0.35:
		_scrape_timer -= delta
		noise_level = clampf(speed / 5.0, 0.0, 1.0)
		if _scrape_timer <= 0.0:
			_scrape_timer = 0.22
			Audio.play_scrape(material_kind, global_position, clampf(speed / 4.0, 0.2, 1.0))
			_notify_noise(noise_level * 0.5)
			if speed > 1.6 and holders.size() < maxi(1, min_carriers):
				take_damage(0.004 * speed * fragility, false)
	_last_speed = speed


func _notify_noise(amount: float) -> void:
	var mission := Game.mission
	if mission != null:
		mission.report_noise(global_position, amount)


func _on_body_entered(body: Node) -> void:
	if _impact_cooldown > 0.0 or not is_alive:
		return
	var impact_speed := maxf(_last_speed, linear_velocity.length())
	if body is Furniture:
		impact_speed = maxf(impact_speed, (linear_velocity - (body as Furniture).linear_velocity).length())
	if impact_speed < 1.6:
		return
	_impact_cooldown = 0.12
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer or Net.is_host()):
		return
	var intensity := clampf(impact_speed / 12.0, 0.05, 1.0)
	Audio.play_impact(material_kind, intensity, global_position)
	_notify_noise(intensity)
	if not is_held() and impact_speed > 3.2:
		var amount := (impact_speed - 3.0) / 26.0 * (0.35 + fragility)
		take_damage(amount * impact_damage_scale(), false)
	if intensity > 0.35 and creature_flag:
		_wake_creature()


## Heavy Suspension upgrade: a load strapped down in the bay rides out impacts that would
## otherwise cost the crew money. Returns the multiplier applied to impact damage.
func impact_damage_scale() -> float:
	if not Save.owns_upgrade("truck_suspension"):
		return 1.0
	var mission := Game.mission
	if mission == null or mission.truck == null:
		return 1.0
	return 0.5 if mission.truck.is_inside_cargo(self) else 1.0


func take_damage(amount: float, broadcast := true) -> void:
	if not is_alive or amount <= 0.0:
		return
	damage = clampf(damage + amount, 0.0, MAX_DAMAGE)
	damaged.emit(amount, damage >= MAX_DAMAGE)
	_tint_for_damage()
	if broadcast and Net.is_online():
		rpc("_rpc_damage", damage)
	if damage >= MAX_DAMAGE:
		destroy_object()


@rpc("authority", "call_remote", "reliable")
func _rpc_damage(value: float) -> void:
	damage = value
	_tint_for_damage()


func _tint_for_damage() -> void:
	if _mesh_instance == null or damage <= 0.001:
		return
	var mat: StandardMaterial3D = null
	if _mesh_instance.has_meta("dmg_mat"):
		mat = _mesh_instance.get_meta("dmg_mat") as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.9
		_mesh_instance.set_meta("dmg_mat", mat)
	var t := clampf(damage, 0.0, 1.0)
	mat.albedo_color = Color(1.0 - 0.45 * t, 1.0 - 0.5 * t, 1.0 - 0.55 * t)
	_mesh_instance.material_override = mat


func destroy_object() -> void:
	if not is_alive:
		return
	is_alive = false
	release_all()
	Audio.play_impact(material_kind, 1.0, global_position)
	_spawn_debris()
	if Net.is_online():
		rpc("_rpc_destroyed")
	var mission := Game.mission
	if mission != null:
		mission.on_furniture_destroyed(self)
	queue_free()


@rpc("authority", "call_remote", "reliable")
func _rpc_destroyed() -> void:
	is_alive = false
	_spawn_debris()
	queue_free()


func _spawn_debris() -> void:
	# Simple, cheap debris: a handful of physics-free shards.
	var parent := get_parent()
	if parent == null:
		return
	for i in 6:
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.05, 0.16)
		bm.size = Vector3(s, s * 0.6, s)
		shard.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _base_color.darkened(0.2)
		mat.vertex_color_use_as_albedo = false
		shard.material_override = mat
		shard.position = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.5), randf_range(-0.3, 0.3))
		parent.add_child(shard)
		var tw := shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "position", shard.position + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), 1.4)
		tw.tween_property(shard, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 1.4)
		tw.chain().tween_callback(shard.queue_free)


func _wake_creature() -> void:
	var mission := Game.mission
	if mission != null:
		mission.on_living_furniture_agitated(self)


# ------------------------------------------------------------- networking ---

## Packs the runtime state the host wants to replicate (11 floats).
func pack_state(buf: PackedFloat32Array) -> void:
	var q := global_transform.basis.get_rotation_quaternion()
	buf.append(global_position.x)
	buf.append(global_position.y)
	buf.append(global_position.z)
	buf.append(q.x)
	buf.append(q.y)
	buf.append(q.z)
	buf.append(q.w)
	buf.append(linear_velocity.x)
	buf.append(linear_velocity.y)
	buf.append(linear_velocity.z)
	buf.append(damage)


func unpack_state(buf: PackedFloat32Array, offset: int, snap := false) -> void:
	_sync_target_xf = Transform3D(
		Basis(Quaternion(buf[offset + 3], buf[offset + 4], buf[offset + 5], buf[offset + 6])),
		Vector3(buf[offset], buf[offset + 1], buf[offset + 2]))
	_sync_target_lin = Vector3(buf[offset + 7], buf[offset + 8], buf[offset + 9])
	damage = buf[offset + 10]
	_sync_has_target = true
	if snap:
		global_transform = _sync_target_xf
		_tint_for_damage()


func _apply_remote_interpolation(delta: float) -> void:
	if not _sync_has_target:
		return
	var t := clampf(delta * 12.0, 0.0, 1.0)
	global_transform = global_transform.interpolate_with(_sync_target_xf, t)


# --------------------------------------------------------------- delivery ---

func current_value() -> int:
	var mult := clampf(1.0 - damage * 0.85, 0.15, 1.0)
	return int(round(float(base_value) * mult))


func set_delivered(value: bool) -> void:
	if delivered == value:
		return
	delivered = value
	delivered_state_changed.emit(value)
	if delivered:
		release_all()
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func shake(times := 3) -> void:
	var t := create_tween()
	for i in times:
		t.tween_property(_mesh_instance, "position", Vector3(randf_range(-0.05, 0.05), randf_range(0.0, 0.04), randf_range(-0.05, 0.05)), 0.06)
	t.tween_property(_mesh_instance, "position", Vector3.ZERO, 0.08)
