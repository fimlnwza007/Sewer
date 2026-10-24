## ======================================================
## box_spawner.gd — สุ่มกระจายกล่องซ่อนตัวทั่วด่าน (Sewer Floor)
##
## - สุ่มจุดกระจายทั่วแมพในแต่ละรอบ
## - กำหนดระยะห่างขั้นต่ำ (min_box_distance = 18.0 ม.) เพื่อไม่ให้อยู่ใกล้กันเกินไป
## - ตรวจจับระดับพื้นท่อระบายน้ำจริง (-1.2 <= Y <= -0.2)
## - วางกล่องแรกไว้ใกล้ผู้เล่นเล็กน้อยเพื่อให้ทดสอบได้ทันที
## ======================================================
extends Node3D

@export var box_scene: PackedScene = preload("res://scenes/hiding_box.tscn")
@export var max_boxes: int = 7
@export var min_box_distance: float = 18.0
@export var map_min: Vector2 = Vector2(-38.0, -38.0)
@export var map_max: Vector2 = Vector2( 38.0,  38.0)
@export var height_offset: float = 0.02

var _spawned_boxes: Array[Node] = []

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_spawn_all_boxes()

func _spawn_all_boxes() -> void:
	var space := get_world_3d().direct_space_state
	var spawned := 0

	# 1. วางกล่องแรกใกล้ตำแหน่งเริ่มต้นของผู้เล่น (ประมาณ 6 ม. กำลังดี)
	var player: Node = null
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	else:
		player = get_tree().get_root().find_child("player", true, false)

	if player != null:
		var p_pos: Vector3 = player.global_position
		var starter_offsets := [
			Vector3(0, 0, -5.5), Vector3(0, 0, 5.5),
			Vector3(5.5, 0, 0), Vector3(-5.5, 0, 0),
			Vector3(4.0, 0, 4.0), Vector3(-4.0, 0, -4.0)
		]
		for offset_test in starter_offsets:
			var test_origin = p_pos + offset_test + Vector3(0, 0.5, 0)
			var q := PhysicsRayQueryParameters3D.create(test_origin, test_origin + Vector3(0, -3.0, 0))
			var res := space.intersect_ray(q)
			if not res.is_empty():
				var hit_pos: Vector3 = res["position"]
				var normal: Vector3 = res.get("normal", Vector3.UP)
				if normal.y >= 0.7 and hit_pos.y <= -0.2 and hit_pos.y >= -1.2:
					if _check_box_clearance(space, hit_pos):
						_instantiate_box(hit_pos + Vector3(0, height_offset, 0))
						spawned += 1
						print("BoxSpawner: Starter hiding box spawned near player at ", hit_pos)
						break

	# 2. สุ่มกระจายกล่องที่เหลือทั่วด่าน โดยต้องห่างกันอย่างน้อย min_box_distance
	var max_attempts := 450
	var attempts := 0
	while spawned < max_boxes and attempts < max_attempts:
		attempts += 1
		if _try_spawn_random_box(space):
			spawned += 1

	print("BoxSpawner: Successfully spawned %d / %d hiding boxes across sewer map!" % [spawned, max_boxes])

func _try_spawn_random_box(space: PhysicsDirectSpaceState3D) -> bool:
	var rx := randf_range(map_min.x, map_max.x)
	var rz := randf_range(map_min.y, map_max.y)

	var origin := Vector3(rx, 0.5, rz)
	var target := Vector3(rx, -2.5, rz)
	var q := PhysicsRayQueryParameters3D.create(origin, target)
	var result := space.intersect_ray(q)
	if result.is_empty():
		return false

	var normal: Vector3 = result.get("normal", Vector3.UP)
	if normal.y < 0.7:
		return false

	var hit_pos: Vector3 = result["position"]
	# พื้นท่อระบายน้ำจริงต้องอยู่ที่ Y ระหว่าง -1.2 ถึง -0.2
	if hit_pos.y > -0.2 or hit_pos.y < -1.2:
		return false

	# เช็คพื้นที่โล่งรอบตัวกล่อง
	if not _check_box_clearance(space, hit_pos):
		return false

	var spawn_pos := hit_pos + Vector3(0, height_offset, 0)

	# เช็คระยะห่างไม่ให้กล่องอยู่ใกล้กันเกินไป
	for existing in _spawned_boxes:
		if is_instance_valid(existing):
			var dist: float = existing.global_position.distance_to(spawn_pos)
			if dist < min_box_distance:
				return false

	_instantiate_box(spawn_pos)
	return true

func _check_box_clearance(space: PhysicsDirectSpaceState3D, floor_pos: Vector3) -> bool:
	# ตรวจความสูงแนวตั้ง 1.2 ม. เหนือพื้น
	var vert_q := PhysicsRayQueryParameters3D.create(floor_pos + Vector3(0, 0.1, 0), floor_pos + Vector3(0, 1.2, 0))
	if not space.intersect_ray(vert_q).is_empty():
		return false

	# ตรวจว่าไม่ติดกำแพงด้านข้าง (รัศมี 0.65 ม.)
	var side_checks := [Vector3(0.65, 0.4, 0), Vector3(-0.65, 0.4, 0), Vector3(0, 0.4, 0.65), Vector3(0, 0.4, -0.65)]
	for sc in side_checks:
		var sq := PhysicsRayQueryParameters3D.create(floor_pos + Vector3(0, 0.4, 0), floor_pos + sc)
		if not space.intersect_ray(sq).is_empty():
			return false

	return true

func _instantiate_box(pos: Vector3) -> Node:
	var inst: Node = box_scene.instantiate()
	get_tree().current_scene.add_child(inst)
	inst.global_position = pos
	inst.global_rotation = Vector3(0, randf_range(0, TAU), 0)
	_spawned_boxes.append(inst)
	return inst
