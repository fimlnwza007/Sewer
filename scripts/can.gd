## ======================================================
## can.gd — กระป๋องที่ผู้เล่นเก็บและโยนได้ (พร้อม Highlight & Noise)
##
## - มี OmniLight3D + วงแหวน Highlight เรืองแสง มองเห็นชัดในความมืด
## - เก็บได้โดยกดปุ่ม/F หรือเดินชน
## - โยนได้ → กระทบพื้น/ผนัง (ไม่ชนตัวผู้เล่น) → เล่นเสียง 3D ที่จุดตก → ส่งเสียงล่อผี
## - เมื่อกระทบแล้ว จะหายไป (fade out) และแจ้งให้ can_spawner สุ่มเกิดใหม่
## ======================================================
extends RigidBody3D

@export var sfx_impact: AudioStream = null
## ระยะที่ผีได้ยินเสียงกระป๋อง
@export var noise_radius: float = 25.0
## ระยะ pickup ของผู้เล่น
@export var pickup_range: float = 3.2

signal picked_up(can_node: Node)
signal thrown(position: Vector3, radius: float)
signal can_consumed(can_node: Node)

@onready var _light: OmniLight3D = get_node_or_null("OmniLight3D")

var _audio: AudioStreamPlayer3D = null
var _highlight_mesh: MeshInstance3D = null
var _is_held: bool = false
var _is_thrown: bool = false
var _is_consumed: bool = false
var _bounce_count: int = 0
const MAX_BOUNCES_FOR_NOISE: int = 3

func _ready() -> void:
	add_to_group("can")
	contact_monitor = true
	max_contacts_reported = 4

	_audio = AudioStreamPlayer3D.new()
	_audio.max_distance = noise_radius
	_audio.unit_size = 4.0
	_audio.volume_db = 6.0
	_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_audio)

	# ตั้งค่าแสง OmniLight3D ให้สว่างเรืองแสงสีทองส้ม
	#if _light:
		#_light.light_color = Color(1.0, 0.85, 0.35)
		#_light.light_energy = 2.0
		#_light.omni_range = 2.8
		#_light.shadow_enabled = false

	# สร้างวงแหวน Highlight เรืองแสง (Torus) ที่พื้นใต้กระป๋อง
	
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _is_held or _is_consumed:
		return

	# แสงกะพริบเป็นจังหวะ Pulse
	if _light and _light.visible:
		_light.light_energy = 1.8 + sin(Time.get_ticks_msec() * 0.005) * 0.8

	# หมุนวงแหวน Highlight ช้าๆ
	if _highlight_mesh and _highlight_mesh.visible:
		_highlight_mesh.rotate_y(delta * 1.5)

func _on_body_entered(body: Node) -> void:
	if _is_held or _is_consumed:
		return

	# สำคัญมาก: หากเป็นตัว Player ห้ามเล่นเสียงกระทบ และห้าม alert ผีเด็ดขาด!
	if body.is_in_group("player"):
		if not _is_thrown and body.has_method("pickup_can_direct"):
			body.pickup_can_direct(self)
		return

	# เล่นเสียงกระทบ 3D เฉพาะเมื่อชนพื้นหรือผนังเท่านั้น
	if sfx_impact and linear_velocity.length() > 0.6:
		# ตรวจสอบกำแพงกั้นเสียงถึงผู้เล่น (Audio Occlusion ไม่ให้เสียงทะลุกำแพง)
		var is_blocked := _is_audio_blocked_to_player()
		_audio.volume_db = -18.0 if is_blocked else 6.0
		_audio.stream = sfx_impact
		_audio.play()
		_bounce_count += 1
		if _bounce_count <= MAX_BOUNCES_FOR_NOISE:
			# ส่งเสียงล่อให้ผี alert และวิ่งมาดูที่จุดกระป๋องตก
			thrown.emit(global_position, noise_radius)

	# ถ้ากระป๋องนี้ถูกโยนมาและกระทบพื้น/ผนังแล้ว ให้เริ่มนับเวลาหายไป แล้วสุ่มเกิดใหม่
	if _is_thrown and not _is_consumed:
		_start_disappear_and_respawn()

func _is_audio_blocked_to_player() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	var p: Node = players[0]
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.2, 0),
		p.global_position + Vector3(0, 0.8, 0),
		collision_mask,
		[self, p]
	)
	var res := space.intersect_ray(query)
	if res.is_empty():
		return false
	var col: Node = res.get("collider") as Node
	if col == null or col == self or col == p:
		return false
	return true

func _start_disappear_and_respawn() -> void:
	if _is_consumed:
		return
	_is_consumed = true

	# ให้ผู้เล่นเห็นและได้ยินเสียงกระป๋องตก กระทบ และกลิ้งไป (1.4 วินาที)
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(self):
		return

	# ค่อยๆ หดตัว Mesh และหรี่แสงลงอย่างนุ่มนวล (ไม่สเกล RigidBody ป้องกัน Jolt warning)
	var mesh_node: Node3D = get_node_or_null("SM_Motel_CrushedCan2")
	var tw := create_tween().set_parallel(true)
	if mesh_node:
		tw.tween_property(mesh_node, "scale", Vector3.ZERO, 0.4)
	if _highlight_mesh:
		tw.tween_property(_highlight_mesh, "scale", Vector3.ZERO, 0.4)
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, 0.4)
	await tw.finished

	can_consumed.emit(self)
	queue_free()

## เรียกจาก player เมื่อเก็บกระป๋อง
func pickup() -> void:
	_is_held = true
	_is_thrown = false
	_bounce_count = 0
	freeze = true
	hide()
	if _light:
		_light.hide()
	if _highlight_mesh:
		_highlight_mesh.hide()
	var col := get_node_or_null("CollisionShape3D")
	if col is CollisionShape3D:
		col.set_deferred("disabled", true)
	picked_up.emit(self)

## เรียกจาก player เมื่อโยนกระป๋อง
func throw_can(from: Vector3, direction: Vector3, force: float = 12.0, thrower: CollisionObject3D = null) -> void:
	_is_held = false
	_is_thrown = true
	_is_consumed = false
	_bounce_count = 0

	# ป้องกันไม่ให้ชนกับตัว Player ที่เป็นคนโยน
	if thrower != null:
		add_collision_exception_with(thrower)

	global_position = from
	show()
	if _light:
		_light.show()
	if _highlight_mesh:
		_highlight_mesh.show()
	var col := get_node_or_null("CollisionShape3D")
	if col is CollisionShape3D:
		col.set_deferred("disabled", false)
	freeze = false
	linear_velocity = direction * force
	angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))

	# Failsafe: หากโยนแล้วไม่ชนอะไรเลยภายใน 7 วินาที ให้หายไปและเกิดใหม่
	get_tree().create_timer(7.0).timeout.connect(func():
		if _is_thrown and not _is_consumed and is_instance_valid(self):
			_start_disappear_and_respawn()
	)
