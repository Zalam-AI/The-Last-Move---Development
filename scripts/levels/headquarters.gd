extends Node3D
## LAST MOVE INCORPORATED - headquarters.
## A persistent social space: contract board, equipment store, uniform lockers, the
## performance board, the truck bay, a break room with a training video nobody watches,
## and a PA system that treats supernatural incidents as an administrative matter.

const H := 4.2
const W := 34.0
const D := 24.0

var _contract_slots: Array[Interactable] = []
var _pa_timer := 45.0
var _announce_index := 0


func _ready() -> void:
	_build()
	Audio.play_music("hq_lobby", 1.5)
	Audio.play_ambience("hq_lobby", 2.0, -12.0)
	# one-time orientation. The room is legible, but nobody has ever walked into a fictional
	# moving company before and known which wall the work is on.
	if not Save.has_seen_hint("hq_intro"):
		Save.mark_hint_seen("hq_intro")
		var t := get_tree().create_timer(1.2)
		t.timeout.connect(func():
			Game.ui.notify("LAST MOVE INC. Contract board on the far wall, equipment room north-west, and nobody has ever been promoted.", "hint"))


func get_spawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, 10.0))


func _build() -> void:
	var geo := MeshBuilder.new()
	LevelKit.make_environment(self, "indoor_luxury")
	# floor / ceiling
	geo.box(Vector3(W, 0.3, D), Vector3(0, -0.15, 0), Color("#3d4148"))
	geo.box(Vector3(W, 0.2, D), Vector3(0, H + 0.1, 0), Color("#22262c"))
	# walls
	LevelKit.wall(geo, Vector3(-W * 0.5, 0, D * 0.5), Vector3(W * 0.5, 0, D * 0.5), H, 0.3, Color("#4a4f56"),
		[{"center": W * 0.5, "width": 4.0, "height": 2.6}])
	LevelKit.wall(geo, Vector3(-W * 0.5, 0, -D * 0.5), Vector3(W * 0.5, 0, -D * 0.5), H, 0.3, Color("#4a4f56"))
	LevelKit.wall(geo, Vector3(-W * 0.5, 0, -D * 0.5), Vector3(-W * 0.5, 0, D * 0.5), H, 0.3, Color("#4a4f56"))
	LevelKit.wall(geo, Vector3(W * 0.5, 0, -D * 0.5), Vector3(W * 0.5, 0, D * 0.5), H, 0.3, Color("#4a4f56"))

	# equipment room (NW)
	LevelKit.wall(geo, Vector3(-9, 0, -12), Vector3(-9, 0, -6), H, 0.2, Color("#3f444b"),
		[{"center": 3.0, "width": 2.2, "height": 2.4}])
	LevelKit.wall(geo, Vector3(-17, 0, -6), Vector3(-9, 0, -6), H, 0.2, Color("#3f444b"),
		[{"center": 5.0, "width": 2.0, "height": 2.4}])
	# garage bay (NE)
	LevelKit.wall(geo, Vector3(8, 0, -12), Vector3(8, 0, 0), 3.4, 0.25, Color("#3a3f46"),
		[{"center": 7.0, "width": 4.2, "height": 3.2}])
	LevelKit.wall(geo, Vector3(8, 0, 0), Vector3(17, 0, 0), 3.4, 0.25, Color("#3a3f46"),
		[{"center": 4.5, "width": 3.0, "height": 3.2}])
	# break room (SE)
	LevelKit.wall(geo, Vector3(9, 0, 2), Vector3(17, 0, 2), 2.9, 0.2, Color("#43484f"),
		[{"center": 4.0, "width": 2.0, "height": 2.3}])
	LevelKit.wall(geo, Vector3(9, 0, 2), Vector3(9, 0, 12), 2.9, 0.2, Color("#43484f"),
		[{"center": 5.0, "width": 2.0, "height": 2.3}])

	# ceiling beams
	for i in 6:
		geo.box(Vector3(W, 0.25, 0.3), Vector3(0, H - 0.2, -10.0 + i * 4.0), Color("#2b3037"))
	# reception desk
	geo.box(Vector3(5.0, 1.1, 1.2), Vector3(-8, 0.55, 4.0), Color("#5b4a36"))
	geo.box(Vector3(5.2, 0.1, 1.35), Vector3(-8, 1.13, 4.0), Color("#8a7a5a"))
	geo.box(Vector3(0.9, 0.7, 0.05), Vector3(-8, 1.5, 4.68), Color("#e8e2d2"))
	# containers / props
	geo.box(Vector3(1.2, 2.2, 0.8), Vector3(-16.3, 1.1, 8.0), Color("#3f4a56"))   # shipping crates
	for i in 3:
		geo.box(Vector3(1.0, 1.0, 1.0), Vector3(6.0, 0.5 + i * 0.1, -9.0 + i * 1.2), Color("#6b5a3f"))
	# lockers along west wall
	for i in 8:
		geo.box(Vector3(0.6, 2.0, 0.9), Vector3(-16.4, 1.0, -4.0 + i * 1.05), Color("#3c5a6b"), MeshBuilder.Mat.METAL)
	# vending machine + table in break room
	geo.box(Vector3(1.0, 2.0, 0.8), Vector3(10.0, 1.0, 3.2), Color("#7a2a2a"))
	geo.box(Vector3(0.7, 1.2, 0.05), Vector3(10.0, 1.4, 3.62), Color(1.0, 0.85, 0.5), MeshBuilder.Mat.EMISSIVE)
	geo.box(Vector3(1.8, 0.08, 1.0), Vector3(13.0, 0.75, 6.0), Color("#8a7a5a"))
	for sx in [-1.0, 1.0]:
		geo.box(Vector3(0.1, 0.75, 0.9), Vector3(13.0 + sx * 0.8, 0.37, 6.0), Color("#6b5a44"))
	geo.commit_static(self, "Architecture", true)

	# reception sign
	_sign("LAST MOVE INC.", Vector3(-8, 2.4, 11.7), 0.0, 120, Color("#e8b13a"))
	_sign("EMPLOYEES ONLY BEYOND THIS POINT", Vector3(0, 3.2, -11.6), 0.0, 64, Color("#c8c2b2"))
	_sign("TRUCK BAY", Vector3(8, 3.6, -6.0), PI * 0.5, 48, Color("#c8c2b2"))
	_sign("BREAK ROOM", Vector3(13.0, 3.0, 1.9), 0.0, 48, Color("#c8c2b2"))

	_build_lighting()
	_build_contract_board()
	_build_stations()
	_build_truck()
	_build_training_video()


func _sign(text: String, pos: Vector3, yaw: float, size: int, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.004 * (size / 64.0)
	l.modulate = color
	l.position = pos
	l.rotation.y = yaw
	l.no_depth_test = false
	add_child(l)


func _build_lighting() -> void:
	LevelKit.moonlight(self, 0.22, Color(0.5, 0.6, 0.9), Vector3(-1.0, 0.6, 0.4))
	for i in 5:
		LevelKit.corridor_strip(self, Vector3(0, H - 0.35, -8.0 + i * 4.5), 6.0, 0.0, Color(0.9, 0.95, 1.0), 1.1)
	LevelKit.lamp(self, Vector3(-8, 2.1, 4.0), Color(1.0, 0.82, 0.55), 1.6, 8.0, true)
	LevelKit.lamp(self, Vector3(-13, 3.0, -9.0), Color(1.0, 0.9, 0.75), 1.3, 8.0)
	LevelKit.lamp(self, Vector3(12.5, 3.2, -6.0), Color(0.85, 0.92, 1.0), 1.5, 11.0, true)
	LevelKit.lamp(self, Vector3(13.0, 2.5, 7.0), Color(1.0, 0.85, 0.65), 1.2, 8.0)


func _build_contract_board() -> void:
	# big board on the north wall with one card per property
	var board := MeshBuilder.new()
	board.box(Vector3(17.0, 3.1, 0.12), Vector3(0, 2.1, -11.55), Color("#4a3a28"))
	board.box(Vector3(16.4, 2.7, 0.06), Vector3(0, 2.1, -11.47), Color("#c8b48a"))
	board.commit_static(self, "ContractBoard", false)
	_sign("CONTRACT BOARD  •  AVAILABLE WORK", Vector3(0, 3.9, -11.4), 0.0, 56, Color("#e8b13a"))

	var props := DB.properties
	for i in props.size():
		var prop: Dictionary = props[i]
		var col := i % 4
		var row := i / 4
		var x := -6.0 + col * 4.0
		var y := 2.7 - row * 1.2
		var it := Interactable.new()
		it.name = "Contract_%s" % prop["id"]
		it.setup(str(prop.get("title", "")), "[E] accept contract", Vector3(x, y, -11.4), Vector3(1.7, 0.5, 0.2))
		it.activated.connect(_on_contract_chosen.bind(str(prop["id"])))
		add_child(it)
		_contract_slots.append(it)
		var card := MeshBuilder.new()
		var unlocked := Save.is_property_unlocked(str(prop["id"]))
		var done := Save.has_completed(str(prop["id"]))
		var paper := Color("#f0e8d4") if unlocked else Color("#7a756a")
		card.box(Vector3(3.4, 0.9, 0.05), Vector3(x, y, -11.38), paper)
		card.commit_static(self, "Card_%d" % i, false)
		var label := Label3D.new()
		label.text = "%s\n%s\n%s" % [prop.get("code", ""), prop.get("title", ""),
			"COMPLETED" if done else ("%s • %s" % [prop.get("difficulty", ""), U.fmt_clock(float(prop.get("deadline", 0)))])]
		label.font_size = 40
		label.pixel_size = 0.0032
		label.modulate = Color("#2a2620") if unlocked else Color("#cfc9bb")
		label.position = Vector3(x, y + 0.06, -11.33)
		label.width = 400
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(label)


func _on_contract_chosen(by_player: Node, property_id: String) -> void:
	if not Net.is_host():
		Game.ui.notify("Only the host can accept a contract.", "warning")
		return
	if not Save.is_property_unlocked(property_id):
		var props := DB.properties
		for i in props.size():
			if props[i]["id"] == property_id and i > 0:
				Game.ui.notify("Locked. Finish %s first." % props[i - 1].get("title", "the previous contract"), "warning")
				return
		return
	Audio.play_sfx("paper", by_player.global_position if by_player else global_position, -6.0)
	Game.start_mission(property_id)


func _build_stations() -> void:
	var shop := Interactable.new()
	shop.name = "EquipmentStation"
	shop.setup("Equipment Storage", "[E] spend crew credits", Vector3(-13.0, 1.1, -6.8), Vector3(1.4, 0.8, 0.6))
	shop.activated.connect(func(_p): Game.ui.open_shop())
	add_child(shop)
	var shop_mesh := MeshBuilder.new()
	shop_mesh.box(Vector3(2.8, 1.0, 0.8), Vector3(-13.0, 0.5, -6.9), Color("#3f4a56"), MeshBuilder.Mat.METAL)
	shop_mesh.box(Vector3(2.9, 0.08, 0.9), Vector3(-13.0, 1.03, -6.9), Color("#8a7a5a"))
	shop_mesh.commit_static(self, "ShopCounter", false)
	_sign("EQUIPMENT", Vector3(-13.0, 1.9, -6.5), 0.0, 48, Color("#e8b13a"))

	var locker := Interactable.new()
	locker.name = "LockerStation"
	locker.setup("Uniform Locker", "[E] change uniform", Vector3(-16.0, 1.1, 1.0), Vector3(0.8, 1.0, 2.0))
	locker.activated.connect(func(_p): Game.ui.open_cosmetics())
	add_child(locker)
	_sign("UNIFORMS", Vector3(-16.0, 2.4, 1.0), PI * 0.5, 44, Color("#e8b13a"))

	var perf := Interactable.new()
	perf.name = "PerformanceBoard"
	perf.setup("Performance Board", "[E] review company records", Vector3(7.9, 1.6, 6.0), Vector3(0.3, 0.9, 1.6))
	perf.activated.connect(func(_p): Game.ui.open_progress())
	add_child(perf)
	var board := MeshBuilder.new()
	board.box(Vector3(0.1, 2.0, 3.2), Vector3(8.0, 1.8, 6.0), Color("#3a2e22"))
	board.box(Vector3(0.06, 1.8, 3.0), Vector3(7.93, 1.8, 6.0), Color("#d8cfb8"))
	board.commit_static(self, "PerfBoard", false)
	_sign("PERFORMANCE", Vector3(7.85, 3.1, 6.0), -PI * 0.5, 48, Color("#e8b13a"))

	var vending := Interactable.new()
	vending.name = "Vending"
	vending.setup("Vending Machine", "[E] insert company scrip", Vector3(10.0, 1.2, 3.6), Vector3(0.6, 1.0, 0.5))
	vending.activated.connect(func(_p):
		Game.ui.notify("The machine takes the credits and dispenses a note: 'OUT OF ORDER SINCE 1987'.", "warning")
		Audio.play_sfx("vending", Vector3(10, 1.2, 3.6), -6.0))
	add_child(vending)


func _build_truck() -> void:
	var t := Truck.new()
	t.name = "HQTruck"
	t.setup(Truck.BASE_CAPACITY, true)
	t.position = Vector3(12.5, 0, -6.0)
	t.rotation.y = PI * 0.5
	add_child(t)


func _build_training_video() -> void:
	# A CRT in the break room looping the mandatory training video.
	var mi := MeshInstance3D.new()
	var b := MeshBuilder.new()
	b.box(Vector3(1.1, 0.8, 0.5), Vector3.ZERO, Color("#2a2a2e"))
	b.box(Vector3(0.9, 0.62, 0.05), Vector3(0, 0.02, 0.26), Color(0.35, 0.6, 0.5), MeshBuilder.Mat.EMISSIVE)
	mi.mesh = b.build_mesh()
	mi.position = Vector3(14.2, 1.35, 2.6)
	mi.rotation.y = -PI * 0.6
	add_child(mi)
	var light := OmniLight3D.new()
	light.position = Vector3(14.2, 1.5, 3.2)
	light.light_color = Color(0.4, 0.9, 0.7)
	light.light_energy = 0.7
	light.omni_range = 3.5
	add_child(light)


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_pa_timer -= delta
	if _pa_timer <= 0.0:
		_pa_timer = randf_range(70.0, 130.0)
		_play_announcement()


func _play_announcement() -> void:
	var announcements: Array = DB.flavor.get("announcements", [])
	if announcements.is_empty():
		return
	_announce_index = (_announce_index + 1) % announcements.size()
	var text: String = announcements[_announce_index]
	var clip := "announcement_%02d" % (_announce_index + 1)
	Audio.play_voice(clip, "PA: " + text, -3.0)
	if Net.is_online():
		rpc("_rpc_announce", clip, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_announce(clip: String, text: String) -> void:
	Audio.play_voice(clip, "PA: " + text, -3.0)
