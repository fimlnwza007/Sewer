## ======================================================
## can_spawner.gd — Spawn กระป๋องสุ่มทั่วแมพ (Sewer Floor version)
##
## - ตรวจจับระดับพื้นท่อระบายน้ำจริง (Y อยู่ระหว่าง -1.2 ถึง -0.3)
## - วางกระป๋องแรกใกล้ผู้เล่นทันทีเพื่อให้เห็นและทดสอบได้เลย
## - เมื่อกระป๋องที่โยนหายไป (can_consumed) จะสุ่ม spawn กระป๋องใหม่ขึ้นมาทดแทน
## ======================================================
extends Node3D

@export var can_scene: PackedScene = null
@export var max_cans: int = 10
## ขอบเขตแมพ X/Z
@export var map_min: Vector2 = Vector2(-35.0, -35.0)
@export var map_max: Vector2 = Vector2( 35.0,  35.0)
## ความสูงเหนือพื้นเล็กน้อยเพื่อไม่ให้จม
@export var height_offset: float = 0.05

var _spawned: Array[Node] = []
var _ghost: Node = null

func _ready() -> void:
	if can_scene == null:
		push_error("CanSpawner: can_scene is null!")
		return
	# รอ physics frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ghost = _find_ghost()
	_spawn_all()

func _find_ghost() -> Node:
	var g := get_tree().get_nodes_in_group("phee_tor")
	if g.size() > 0:
		return g[0]
	return get_tree().get_root().find_child("PheeTor", true, false)

func _spawn_all() -> void:
	var space := get_world_3d().direct_space_state
	var spawned := 0

	# 1. วางกระป๋องแรกใกล้ตำแหน่งเริ่มต้นของผู้เล่น (เพื่อให้เห็นและทดสอบได้ทันที)
	var player: Node = null
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	else:
		player = get_tree().get_root().find_child("player", true, false)

	if player != null:
		var p_pos: Vector3 = player.global_position
		for offset_test in [Vector3(0, 0, -3.0), Vector3(0, 0, 3.0), Vector3(3.0, 0, 0), Vector3(-3.0, 0, 0)]:
			var test_origin = p_pos + offset_test + Vector3(0, 0.5, 0)
			var q := PhysicsRayQueryParameters3D.create(test_origin, test_origin + Vector3(0, -3.0, 0))
			var res := space.intersect_ray(q)
			if not res.is_empty():
				var hit_pos: Vector3 = res["position"]
				if hit_pos.y <= 0.0 and hit_pos.y >= -1.2:
					_instantiate_can(hit_pos + Vector3(0, height_offset, 0))
					spawned += 1
					print("CanSpawner: Starter can spawned near player at ", hit_pos)
					break

	# 2. สุ่มกระจายกระป๋องที่เหลือทั่วแมพ
	var max_attempts := 350
	var attempts := 0
	while spawned < max_cans and attempts < max_attempts:
		attempts += 1
		if _try_spawn_random_can():
			spawned += 1

	print("CanSpawner: successfully spawned %d / %d cans in sewer corridors" % [spawned, max_cans])

func _try_spawn_random_can() -> bool:
	var space := get_world_3d().direct_space_state
	var rx := randf_range(map_min.x, map_max.x)
	var rz := randf_range(map_min.y, map_max.y)

	# ยิง Ray จากระดับ 0.5 (ภายในอุโมงค์ท่อระบายน้ำ) ลงไปที่ -2.5
	var origin := Vector3(rx, 0.5, rz)
	var target := Vector3(rx, -2.5, rz)
	var q := PhysicsRayQueryParameters3D.create(origin, target)
	var result := space.intersect_ray(q)
	if result.is_empty():
		return false

	var normal: Vector3 = result.get("normal", Vector3.UP)
	if normal.y < 0.7:
		return false  # ต้องเป็นพื้น

	var hit_pos: Vector3 = result["position"]
	# พื้นท่อระบายน้ำจริงต้องอยู่ที่ Y ประมาณ -0.7 (อยู่ระหว่าง -1.2 ถึง -0.3)
	if hit_pos.y > -0.2 or hit_pos.y < -1.2:
		return false

	# ตรวจสอบพื้นที่โล่งด้านบน
	var clearance_q := PhysicsRayQueryParameters3D.create(hit_pos + Vector3(0, 0.1, 0), hit_pos + Vector3(0, 1.2, 0))
	var clearance_res := space.intersect_ray(clearance_q)
	if not clearance_res.is_empty():
		return false

	var spawn_pos := hit_pos + Vector3(0, height_offset, 0)

	# ตรวจสอบระยะห่างจากกระป๋องอื่น
	for existing in _spawned:
		if is_instance_valid(existing) and existing.global_position.distance_to(spawn_pos) < 3.5:
			return false

	_instantiate_can(spawn_pos)
	return true

func _instantiate_can(pos: Vector3) -> Node:
	var inst: Node = can_scene.instantiate()
	get_tree().current_scene.add_child(inst)
	inst.global_position = pos
	inst.global_rotation = Vector3(0, randf_range(0, TAU), 0)

	if inst.has_signal("thrown"):
		inst.thrown.connect(_on_can_thrown)
	if inst.has_signal("can_consumed"):
		inst.can_consumed.connect(_on_can_consumed)

	_spawned.append(inst)
	return inst

func _on_can_thrown(pos: Vector3, radius: float) -> void:
	var ghosts := get_tree().get_nodes_in_group("phee_tor")
	for g in ghosts:
		if is_instance_valid(g) and g.has_method("hear_noise"):
			g.hear_noise(pos, radius)

func _on_can_consumed(can_node: Node) -> void:
	_spawned.erase(can_node)
	print("CanSpawner: Thrown can consumed. Respawning replacement can...")
	# หน่วงเวลาเล็กน้อย 1.5 - 2.5 วินาที แล้วสุ่มเกิดกระป๋องใหม่ในแมพ
	await get_tree().create_timer(randf_range(1.5, 2.5)).timeout
	if not is_inside_tree():
		return

	var spawned := false
	for attempt in range(80):
		if _try_spawn_random_can():
			spawned = true
			print("CanSpawner: Replacement can spawned successfully! Current cans: ", _spawned.size())
			break
	if not spawned:
		print("CanSpawner: Retry needed for replacement can.")
