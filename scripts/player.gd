extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var MOUSE_SENSITIVITY = 0.002

@onready var head: Node3D = $head
@onready var camera: Camera3D = $head/Camera3D

func _ready() -> void:
	pass  # ไม่ lock เมาส์ — ให้ LookZone จัดการหันหน้าทั้งบนมือถือและ PC (emulate_touch_from_mouse)

func _input(event: InputEvent) -> void:
	# Esc สลับ mouse capture บน PC (สำหรับผู้ที่ต้องการ)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# หันหน้าด้วยเมาส์ (PC) — ใช้เมื่อ mouse ถูก capture เท่านั้น
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)

## เรียกจาก LookZone เพื่อหันหน้าบนมือถือ
func apply_look_delta(delta: Vector2) -> void:
	_apply_look(delta)

func _apply_look(delta: Vector2) -> void:
	rotate_y(-delta.x * MOUSE_SENSITIVITY)
	head.rotate_x(-delta.y * MOUSE_SENSITIVITY)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta: float) -> void:
	# แรงโน้มถ่วง
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump (PC)
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# รับ input จาก action "a", "d", "w", "s" (มาจากทั้งปุ่มคีย์บอร์ดและจอยสติ๊ก)
	var input_dir := Input.get_vector("a", "d", "w", "s")
	if input_dir == Vector2.ZERO:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
