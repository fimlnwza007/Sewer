extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var MOUSE_SENSITIVITY = 0.002
@export var TOUCH_SENSITIVITY = 0.006

## ===================== Sneak / Crouch =====================
@export var CROUCH_SPEED: float = 2.2
@export var CROUCH_HEAD_Y: float = 0.2
var _is_crouching: bool = false
var _normal_head_y: float = 0.65
signal crouch_changed(is_crouched: bool)

## ===================== Hiding System =====================
signal hiding_state_changed(is_hidden: bool)
var _is_hidden: bool = false
var _current_box: Node = null
var _pre_hide_pos: Vector3 = Vector3.ZERO
var _original_fov: float = 75.0

## ===================== Health & Death (1-Hit Kill) =====================
signal player_died
var is_dead: bool = false

## ===================== Footstep Sounds =====================
@export_group("Footsteps")
## เสียงเท้าขณะเดินปกติ
@export var sfx_walk: AudioStream = null
## เสียงเท้าขณะวิ่ง (ถ้าไม่ใส่ใช้ sfx_walk แทน)
@export var sfx_run:  AudioStream = null
## ระยะเวลาระหว่างก้าวขณะเดิน (วินาที)
@export var step_interval_walk: float = 0.35
## ระยะเวลาระหว่างก้าวขณะวิ่ง
@export var step_interval_run:  float = 0.28
@export_group("")

@onready var head: Node3D = $head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _footstep_player: AudioStreamPlayer = null
var _step_timer: float = 0.0

## ===================== Can Carry =====================
signal can_state_changed(is_holding: bool)

## กระป๋องที่ถืออยู่ (null = ไม่มี)
var _held_can: Node = null
## ระยะ pickup กระป๋อง (ตรวจ overlap ด้วย distance)
const PICKUP_RANGE: float = 3.2
## แรงโยนกระป๋อง
const THROW_FORCE: float = 11.0

## Multi-touch look tracking
var _look_index: int   = -1
var _look_last:  Vector2 = Vector2.ZERO
var _look_accum: Vector2 = Vector2.ZERO   # สะสม delta ระหว่างเฟรม

## ===================== Ready =====================
func _ready() -> void:
	add_to_group("player")
	_normal_head_y = head.position.y
	var cam := head.get_node_or_null("Camera3D") as Camera3D
	if cam:
		_original_fov = cam.fov

	# สร้าง AudioStreamPlayer สำหรับเสียงเท้า
	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.volume_db = 3.0
	add_child(_footstep_player)

	# PC only: lock mouse
	if OS.get_name() not in ["Android", "iOS"]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# อ่าน Input map สำหรับ pickup/throw และ crouch และ hide
	_ensure_input_actions()

func _ensure_input_actions() -> void:
	if not InputMap.has_action("pickup_throw"):
		InputMap.add_action("pickup_throw")
		var ev := InputEventKey.new()
		ev.keycode = KEY_F
		InputMap.action_add_event("pickup_throw", ev)
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_E
		InputMap.action_add_event("pickup_throw", ev2)

	if not InputMap.has_action("crouch"):
		InputMap.add_action("crouch")
		var ev_c := InputEventKey.new()
		ev_c.keycode = KEY_C
		InputMap.action_add_event("crouch", ev_c)
		var ev_ctrl := InputEventKey.new()
		ev_ctrl.keycode = KEY_CTRL
		InputMap.action_add_event("crouch", ev_ctrl)

	if not InputMap.has_action("hide"):
		InputMap.add_action("hide")
		var ev_h := InputEventKey.new()
		ev_h.keycode = KEY_H
		InputMap.action_add_event("hide", ev_h)

## ===================== Input =====================
func _input(event: InputEvent) -> void:
	# ถ้าตายแล้ว กดปุ่มอะไรให้เริ่มเกมใหม่ได้
	if is_dead:
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_R):
			get_tree().reload_current_scene()
		return

	# ESC toggle mouse lock (PC)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	# กดซ่อน / ออกจากกล่อง (H)
	elif event.is_action_pressed("hide"):
		toggle_hide_in_box()

	# Pickup / Throw / Interact (F หรือ E)
	elif event.is_action_pressed("pickup_throw"):
		if _is_hidden:
			exit_box()
		elif _held_can != null:
			_throw_can()
		else:
			var can_to_pick: Node = get_closest_can_in_range(PICKUP_RANGE)
			if can_to_pick != null:
				_held_can = can_to_pick
				_held_can.pickup()
				can_state_changed.emit(true)
			else:
				var box_nearby: Node = get_closest_hiding_box(2.8)
				if box_nearby != null:
					hide_in_box(box_nearby)

	# ย่อง / ลุกขึ้น (C หรือ Ctrl)
	elif event.is_action_pressed("crouch"):
		if not _is_hidden:
			toggle_crouch()

	# PC mouse look
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_accum += event.relative
		return

	# ===== Touch look (right half of screen — x > 45% of viewport) =====
	elif event is InputEventScreenTouch:
		if event.pressed and _is_touch_on_ui(event.position):
			return
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var in_look_zone: bool = event.position.x >= vp.x * 0.45
		if event.pressed and _look_index == -1 and in_look_zone:
			_look_index = event.index
			_look_last  = event.position
			_look_accum = Vector2.ZERO
		elif not event.pressed and event.index == _look_index:
			_look_index = -1

	elif event is InputEventScreenDrag and event.index == _look_index:
		var raw: Vector2 = event.position - _look_last
		_look_last = event.position
		if raw.length() <= 80.0:
			_look_accum += raw

## ===================== Process =====================
func _process(delta: float) -> void:
	if is_dead:
		return

	if _look_accum != Vector2.ZERO:
		_apply_look(_look_accum)
		_look_accum = Vector2.ZERO

	# เลื่อนระดับมุมมองหัว (Head) ขึ้นลงอย่างนุ่มนวลตอนย่อง หรือตอนแอบในกล่อง
	var target_head_y: float = CROUCH_HEAD_Y if (_is_crouching or _is_hidden) else _normal_head_y
	head.position.y = lerpf(head.position.y, target_head_y, delta * 12.0)

func apply_look_delta(delta: Vector2) -> void:
	_apply_look(delta)

func _apply_look(delta: Vector2) -> void:
	var sens: float = TOUCH_SENSITIVITY if _look_index != -1 else MOUSE_SENSITIVITY
	rotate_y(-delta.x * sens)
	head.rotate_x(-delta.y * sens)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## ===================== Physics =====================
func _physics_process(delta: float) -> void:
	# ถ้าตายแล้ว หยุดอยู่กับที่
	if is_dead:
		velocity = Vector3.ZERO
		return

	# ถ้ากำลังแอบในกล่อง จะไม่เคลื่อนที่และไม่ทำเสียงฝีเท้า
	if _is_hidden:
		velocity = Vector3.ZERO
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump (PC)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement: จากจอยสติ๊ก (action a/d/w/s) หรือ WASD
	var input_dir := Input.get_vector("a", "d", "w", "s")
	if input_dir == Vector2.ZERO:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var move_speed: float = CROUCH_SPEED if _is_crouching else SPEED
	if direction:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

	# ===== Footstep sound (เก็บเสียง ไม่เล่นเมื่อย่อง) =====
	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and flat_speed > 0.5 and not _is_crouching:
		_step_timer -= delta
		if _step_timer <= 0.0:
			var is_running: bool = flat_speed > SPEED * 0.7
			_step_timer = step_interval_run if is_running else step_interval_walk
			var stream := sfx_run if (is_running and sfx_run != null) else sfx_walk
			if stream != null:
				_footstep_player.stream = stream
				_footstep_player.play()
	else:
		_step_timer = 0.0

## ===================== Damage & Death (1-Hit Kill) =====================
func take_damage(_amount: int = 100) -> void:
	if is_dead or _is_hidden:
		return
	is_dead = true
	velocity = Vector3.ZERO

	# แอนิเมชันล้มลงกับพื้น (ตายใน 1 ที)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "position:y", 0.08, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "rotation:z", deg_to_rad(-30.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# ปล่อยเมาส์ให้สามารถกดปุ่มเริ่มเกมใหม่ได้
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	player_died.emit()

## ===================== Hiding Box API =====================
func is_hidden() -> bool:
	return _is_hidden

func get_closest_hiding_box(max_dist: float = 2.8) -> Node:
	var boxes := get_tree().get_nodes_in_group("hiding_box")
	var closest: Node = null
	var closest_dist := max_dist
	for b in boxes:
		if not is_instance_valid(b):
			continue
		if b.has_method("is_occupied") and b.is_occupied():
			continue
		var horiz_d: float = Vector2(global_position.x - b.global_position.x, global_position.z - b.global_position.z).length()
		var vert_d: float = absf(global_position.y - b.global_position.y)
		if horiz_d < closest_dist and vert_d < 2.5:
			closest_dist = horiz_d
			closest = b
	return closest

func hide_in_box(box_node: Node) -> void:
	if _is_hidden or not is_instance_valid(box_node):
		return
	_is_hidden = true
	_current_box = box_node
	_pre_hide_pos = global_position

	if box_node.has_method("set_occupied"):
		box_node.set_occupied(true)

	if collision_shape:
		collision_shape.disabled = true

	velocity = Vector3.ZERO
	if box_node.has_method("get_hiding_position"):
		global_position = box_node.get_hiding_position()

	# หรี่ตามุมมอง: ลด FOV ลงอย่างนุ่มนวล
	var cam := head.get_node_or_null("Camera3D") as Camera3D
	if cam:
		var tw := create_tween()
		tw.tween_property(cam, "fov", 46.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	hiding_state_changed.emit(true)

func exit_box() -> void:
	if not _is_hidden:
		return
	_is_hidden = false

	var exit_pos: Vector3 = global_position
	if is_instance_valid(_current_box):
		if _current_box.has_method("get_exit_position"):
			exit_pos = _current_box.get_exit_position(_pre_hide_pos)
		if _current_box.has_method("set_occupied"):
			_current_box.set_occupied(false)

	_current_box = null

	# ป้องกันการตกแมพ: ยิง Raycast เพื่อหาระดับพื้นจริง ณ จุดที่ก้าวออกมา
	var space := get_world_3d().direct_space_state
	var ray_from := Vector3(exit_pos.x, exit_pos.y + 1.5, exit_pos.z)
	var ray_to   := Vector3(exit_pos.x, exit_pos.y - 3.5, exit_pos.z)
	var q := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var floor_y: float = hit["position"].y
		exit_pos.y = floor_y + 1.02  # Capsule สูง 2.0ม. จุดกึ่งกลาง = floor + 1.02ม.
	elif _pre_hide_pos != Vector3.ZERO:
		exit_pos.y = _pre_hide_pos.y

	# ย้ายตำแหน่งผู้เล่นให้ยืนอยู่บนพื้นอย่างปลอดภัย และรีเซ็ตความเร็วตกค้าง
	global_position = exit_pos
	velocity = Vector3.ZERO

	if collision_shape:
		collision_shape.disabled = false

	# คืนค่ามุมมองปกติ
	var cam := head.get_node_or_null("Camera3D") as Camera3D
	if cam:
		var tw := create_tween()
		tw.tween_property(cam, "fov", _original_fov, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	hiding_state_changed.emit(false)

func toggle_hide_in_box(box_node: Node = null) -> void:
	if _is_hidden:
		exit_box()
	elif box_node != null:
		hide_in_box(box_node)
	else:
		var closest := get_closest_hiding_box(2.8)
		if closest:
			hide_in_box(closest)

## ===================== Crouch / Sneak API =====================
func is_crouching() -> bool:
	return _is_crouching

func set_crouch(crouch: bool) -> void:
	if _is_crouching != crouch:
		_is_crouching = crouch
		crouch_changed.emit(_is_crouching)

func toggle_crouch() -> void:
	set_crouch(not _is_crouching)

## ===================== Can Public API =====================
func is_holding_can() -> bool:
	return _held_can != null

func get_held_can() -> Node:
	return _held_can

func interact_can() -> void:
	_handle_can_interaction()

func pickup_can_direct(can_node: Node) -> void:
	if _held_can == null and is_instance_valid(can_node) and not can_node.get("_is_held"):
		_held_can = can_node
		_held_can.pickup()
		can_state_changed.emit(true)

func get_closest_can_in_range(max_dist: float = PICKUP_RANGE) -> Node:
	var cans := get_tree().get_nodes_in_group("can")
	var closest: Node = null
	var closest_dist := max_dist
	for can in cans:
		if not is_instance_valid(can):
			continue
		if can.has_method("pickup") and not can.get("_is_held"):
			var horiz_d: float = Vector2(global_position.x - can.global_position.x, global_position.z - can.global_position.z).length()
			var vert_d: float = absf(global_position.y - can.global_position.y)
			if horiz_d < closest_dist and vert_d < 2.5:
				closest_dist = horiz_d
				closest = can
	return closest

## ===================== Can Interaction =====================
func _handle_can_interaction() -> void:
	if _held_can != null:
		_throw_can()
	else:
		_try_pickup_can()

func _try_pickup_can() -> void:
	var can_to_pick: Node = get_closest_can_in_range(PICKUP_RANGE)
	if can_to_pick != null:
		_held_can = can_to_pick
		_held_can.pickup()
		can_state_changed.emit(true)

func _throw_can() -> void:
	if _held_can == null:
		return
	var cam: Camera3D = head.get_node_or_null("Camera3D")
	var throw_dir: Vector3
	if cam:
		throw_dir = -cam.global_transform.basis.z
	else:
		throw_dir = -global_transform.basis.z
	throw_dir.y += 0.22
	throw_dir = throw_dir.normalized()

	var cam_pos: Vector3 = cam.global_position if cam else global_position + Vector3(0, 0.6, 0)
	var throw_from: Vector3 = cam_pos + throw_dir * 0.85

	if _held_can.has_method("throw_can"):
		_held_can.throw_can(throw_from, throw_dir, THROW_FORCE, self)
	_held_can = null
	can_state_changed.emit(false)

func _is_touch_on_ui(pos: Vector2) -> bool:
	var buttons := get_tree().get_nodes_in_group("mobile_ui_button")
	for btn in buttons:
		if btn is Control and btn.is_visible_in_tree() and btn.get_global_rect().has_point(pos):
			return true
	return false
