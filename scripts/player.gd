extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var MOUSE_SENSITIVITY = 0.002
@export var TOUCH_SENSITIVITY = 0.006

@onready var head: Node3D = $head

## Multi-touch look tracking
var _look_index: int   = -1
var _look_last:  Vector2 = Vector2.ZERO
var _look_accum: Vector2 = Vector2.ZERO   # สะสม delta ระหว่างเฟรม

## ===================== Ready =====================
func _ready() -> void:
	# PC only: lock mouse
	if OS.get_name() not in ["Android", "iOS"]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## ===================== Input =====================
func _input(event: InputEvent) -> void:
	# ESC toggle mouse lock (PC)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	# PC mouse look
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_accum += event.relative
		return

	# ===== Touch look (right half of screen — x > 45% of viewport) =====
	elif event is InputEventScreenTouch:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var in_look_zone: bool = event.position.x >= vp.x * 0.45
		if event.pressed and _look_index == -1 and in_look_zone:
			_look_index = event.index
			_look_last  = event.position
			_look_accum = Vector2.ZERO
		elif not event.pressed and event.index == _look_index:
			_look_index = -1

	elif event is InputEventScreenDrag and event.index == _look_index:
		# คำนวณ delta จาก position จริงของนิ้วนี้ (ไม่ใช้ event.relative ที่มีบั๊ก multi-touch)
		var raw: Vector2 = event.position - _look_last
		_look_last = event.position
		# Spike guard: ตัดค่าที่กระโดดผิดปกติ (เกิดตอนวางนิ้วที่ 2 ลง)
		if raw.length() <= 80.0:
			_look_accum += raw

## ===================== Process =====================
func _process(_delta: float) -> void:
	if _look_accum != Vector2.ZERO:
		_apply_look(_look_accum)
		_look_accum = Vector2.ZERO

## เรียกได้จาก script อื่นถ้าจำเป็น
func apply_look_delta(delta: Vector2) -> void:
	_apply_look(delta)

func _apply_look(delta: Vector2) -> void:
	var sens: float = TOUCH_SENSITIVITY if _look_index != -1 else MOUSE_SENSITIVITY
	rotate_y(-delta.x * sens)
	head.rotate_x(-delta.y * sens)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## ===================== Physics =====================
func _physics_process(delta: float) -> void:
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
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
