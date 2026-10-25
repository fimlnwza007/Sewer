## ======================================================
## phee_tor.gd — Ghost AI for Maze Horror Game (No NavMesh)
##
## Detection (2 ช่องทาง):
##   - SIGHT: เห็นด้วย FOV + Raycast
##   - SOUND: ได้ยินเสียงเท้า player เมื่อ player กำลังเดิน/วิ่ง
##
## State Machine:
##   IDLE/PATROL → detect player → SCREAM → CHASE
##   CHASE       → สูญเสียตำแหน่ง → ไปที่ last_known_pos → PATROL
##   ATTACK      → จบแอนิเมชั่น → CHASE
## ======================================================
extends CharacterBody3D

## ===================== Sound Exports =====================
@export_group("Sound Effects")
@export var sfx_idle:      AudioStream = null  ## เสียงหายใจ Idle
@export var sfx_footstep:  AudioStream = null  ## เสียงเท้าขณะเดิน
@export var sfx_chase:     AudioStream = null  ## เสียงคำรามขณะไล่
@export var sfx_scream:    AudioStream = null  ## เสียงกรีดร้องตอนเห็น player
@export var sfx_attack:    AudioStream = null  ## เสียงโจมตี
@export var sfx_wall_slam: AudioStream = null  ## เสียงชนกำแพง
@export var sfx_detect:    AudioStream = null  ## เสียงเตือนเมื่อเจอ player
@export_group("")

## ===================== AI Exports =====================
@export_group("Detection")
## ให้ผีมองเห็นผู้เล่นหรือไม่ (true = มองเห็นตามระยะและ FOV)
@export var can_see_player:   bool  = true
## ระยะที่ผีมองเห็น (มีผลเมื่อ can_see_player = true)
@export var sight_range:      float = 18.0
## มุมมอง FOV
@export var fov_degrees:      float = 120.0
## ระยะได้ยินเสียงเท้า player ขณะเดิน
@export var sound_range:      float = 4.0
## ระยะได้ยินเสียงเท้าขณะวิ่ง (ไกลกว่า)
@export var run_sound_range:  float = 7.0
## ระยะที่ผีเลิกไล่ (เมื่อไม่ได้ยินเสียง)
@export var lose_range:       float = 28.0
@export_group("Movement")
@export var patrol_speed:    float = 2.5
@export var chase_speed:     float = 5.6
@export var attack_range:    float = 2.6
@export var attack_cooldown: float = 0.3
@export var damage:          int   = 9999
@export_group("Wander")
## เดินไปทิศหนึ่งกี่วินาทีก่อนเปลี่ยน
@export var wander_duration: float = 6.0
## หยุดรอก่อนเดินใหม่
@export var wander_wait:     float = 1.0
## ระยะ Raycast หลบกำแพง
@export var wall_probe_dist: float = 1.5
@export_group("")

## ===================== State =====================
enum State { IDLE, PATROL, CHASE, INVESTIGATE, ATTACK, SCREAM, WALL_SLAM }
var _state: State = State.IDLE

## ===================== Refs =====================
@onready var _anim: AnimationPlayer = $AnimationPlayer
var _audio_loop:    AudioStreamPlayer3D = null
var _audio_oneshot: AudioStreamPlayer3D = null
var _player: CharacterBody3D = null

## ===================== Internal =====================
var _attack_timer:         float   = 0.0
var _attack_has_hit:       bool    = false
var _attack_duration:      float   = 0.0
var _chase_persist_timer:  float   = 0.0
var _scream_cooldown:      float   = 0.0
var _wander_timer:         float   = 0.0
var _move_dir:             Vector3 = Vector3.ZERO
var _last_known_pos:       Vector3 = Vector3.ZERO  ## ตำแหน่งล่าสุดที่รู้ว่า player อยู่
var _has_last_known:       bool    = false
var _can_see_player:       bool    = false
var _can_hear_player:      bool    = false
var _scream_timer:         float   = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _base_loop_volume: float = 4.0
var _base_oneshot_volume: float = 6.0

# Stuck detection & obstacle navigation
const STUCK_CHECK_INTERVAL: float = 0.5
const STUCK_DIST_THRESHOLD: float = 0.2
var _stuck_timer:       float   = 0.5
var _stuck_dodge_timer: float   = 0.0
var _stuck_dodge_dir:   Vector3 = Vector3.ZERO
var _last_pos:          Vector3 = Vector3.ZERO
var _last_wander_dir:   Vector3 = Vector3.ZERO

const ANIM_IDLE   = "MonsterPSX_Rig|Idle_Watchful"
const ANIM_WALK   = "MonsterPSX_Rig|Walk_Nervous"
const ANIM_RUN    = "MonsterPSX_Rig|Run_Frantic"
const ANIM_ATTACK = "MonsterPSX_Rig|Attack_Lunge"
const ANIM_SCREAM = "MonsterPSX_Rig|Scream_lol"
const ANIM_SLAM   = "MonsterPSX_Rig|WallSlam_Recover"

## ===================== Ready =====================
func _ready() -> void:
	add_to_group("phee_tor")
	_audio_loop = AudioStreamPlayer3D.new()
	_audio_loop.max_distance = 25.0
	_audio_loop.unit_size    = 6.0
	_audio_loop.volume_db    = 4.0
	add_child(_audio_loop)

	_audio_oneshot = AudioStreamPlayer3D.new()
	_audio_oneshot.max_distance = 35.0
	_audio_oneshot.unit_size    = 8.0
	_audio_oneshot.volume_db    = 6.0
	add_child(_audio_oneshot)

	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group("player")
	_player = players[0] if players.size() > 0 else \
			  get_tree().get_root().find_child("player", true, false)

	if _anim:
		_anim.animation_finished.connect(_on_animation_finished)

	_pick_wander_dir()
	_set_state(State.PATROL)

## ===================== Physics =====================
func _physics_process(delta: float) -> void:
	
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_attack_timer -= delta
	_wander_timer -= delta
	_scream_cooldown -= delta

	# ถ้า player ตายแล้ว ให้ผียืนอยู่เฉยๆ ไม่ต้องไล่ต่อ
	if _player and _player.get("is_dead"):
		if _state != State.IDLE:
			_set_state(State.IDLE)
		_tick_idle()
		move_and_slide()
		return

	# อัปเดตการรับรู้ player ทุก frame
	_update_senses()
	_update_audio_occlusion()

	# ถ้า detect player ได้ขณะ PATROL/IDLE/INVESTIGATE
	if (_can_see_player or _can_hear_player) and \
	   _state in [State.IDLE, State.PATROL, State.INVESTIGATE]:
		var p_dist := global_position.distance_to(_player.global_position)
		if p_dist <= attack_range:
			_set_state(State.ATTACK)
		elif p_dist <= 5.0 or _scream_cooldown > 0.0:
			# อยู่ใกล้ (< 5.0m) หรือเพิ่งกรีดร้องไป ไม่ต้องยืนกรีดร้องค้าง ให้พุ่งไล่ทันที!
			_set_state(State.CHASE)
		else:
			_set_state(State.SCREAM)

	match _state:
		State.IDLE:        _tick_idle()
		State.PATROL:      _tick_patrol()
		State.INVESTIGATE: _tick_investigate()
		State.CHASE:       _tick_chase()
		State.SCREAM:
			_scream_timer -= delta
			if _player:
				var to_p := (_player.global_position - global_position)
				to_p.y = 0.0
				if to_p.length() > 0.1:
					look_at(global_position - to_p.normalized(), Vector3.UP)
			var p_dist := global_position.distance_to(_player.global_position) if _player else 999.0
			# ถ้าผู้เล่นเข้ามาในระยะโจมตีตอนกำลังกรีดร้อง ให้ฟันทันที
			if p_dist <= attack_range and not (_player.has_method("is_hidden") and _player.is_hidden()):
				_set_state(State.ATTACK)
			elif _scream_timer <= 0.0 or (_anim and not _anim.is_playing()):
				_set_state(State.CHASE)
		State.ATTACK:
			_tick_attack()
			# เมื่อฟันเสร็จแล้ว (ระยะเวลา 0.45s หรือ animation จบ)
			if _attack_duration <= 0.0 or (_anim and not _anim.is_playing()):
				var dist := global_position.distance_to(_player.global_position) if _player else 999.0
				var is_player_hidden: bool = _player and _player.has_method("is_hidden") and _player.is_hidden()
				if not is_player_hidden and not _player.get("is_dead"):
					if dist <= attack_range and _attack_timer <= 0.0:
						_set_state(State.ATTACK)
					else:
						_set_state(State.CHASE)
				else:
					_set_state(State.IDLE)
		State.WALL_SLAM:
			if _anim and not _anim.is_playing():
				_set_state(State.PATROL)

	move_and_slide()

## ===================== Senses =====================
func _update_senses() -> void:
	if _player == null:
		_can_see_player  = false
		_can_hear_player = false
		return

	# ถ้า player ซ่อนตัวอยู่ในกล่อง ผีจะมองไม่เห็นและไม่ได้ยินอย่างสิ้นเชิง
	if _player.has_method("is_hidden") and _player.is_hidden():
		_can_see_player  = false
		_can_hear_player = false
		return

	var dist := global_position.distance_to(_player.global_position)

	# SIGHT: ถ้า can_see_player = false ผีจะตาบอด มองไม่เห็นผู้เล่น
	if can_see_player:
		_can_see_player = _check_sight(dist)
	else:
		_can_see_player = false

	# SOUND: player กำลังเคลื่อนที่ → ผีได้ยิน
	# ถ้า player ย่อง (crouching) จะเดินเก็บเสียง ผีจะไม่ได้ยินเลย!
	var is_player_sneaking: bool = _player.has_method("is_crouching") and _player.is_crouching()
	if is_player_sneaking:
		_can_hear_player = false
	else:
		var player_speed := Vector3(_player.velocity.x, 0, _player.velocity.z).length()
		var effective_sound_range := run_sound_range if player_speed > 3.5 else sound_range
		var in_range: bool = (player_speed > 0.3) and (dist <= effective_sound_range)
		if in_range:
			# เสียงไม่ทะลุกำแพง: ถ้ามีกำแพงกั้นระหว่าง player กับผี ผีจะไม่ได้ยินเสียงฝีเท้า
			if _is_sound_blocked_by_wall(_player.global_position, global_position):
				_can_hear_player = false
			else:
				_can_hear_player = true
		else:
			_can_hear_player = false

	# อัปเดต last known position เมื่อรู้ตำแหน่ง player
	if _can_see_player or _can_hear_player:
		_last_known_pos = _player.global_position
		_has_last_known = true

func _check_sight(dist: float) -> bool:
	if dist > sight_range: return false
	# ถ้าอยู่ใกล้มาก (< 3.0 ม.) มองเห็นรอบทิศทันทีหากไม่มีกำแพงกั้น
	if dist <= 3.0:
		return not _is_sound_blocked_by_wall(global_position, _player.global_position)

	# ถ้ากำลังไล่ล่าอยู่ (CHASE) ในระยะ 12.0 ม. จะล็อกเป้าต่อเนื่อง ไม่หลุดสายตาง่ายๆ ถ้าไม่มีกำแพงกั้น
	if _state == State.CHASE and dist <= 12.0:
		return not _is_sound_blocked_by_wall(global_position, _player.global_position)

	var to_player := (_player.global_position - global_position).normalized()
	# ตัว model หันไปทาง +Z (ตาม _face_velocity)
	var forward := global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_player))
	if angle > fov_degrees * 0.5: return false

	return not _is_sound_blocked_by_wall(global_position, _player.global_position)

## ===================== State Ticks =====================
func _tick_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _wander_timer <= 0.0:
		_pick_wander_dir()
		_set_state(State.PATROL)

func _tick_patrol() -> void:
	if _wander_timer <= 0.0:
		_wander_timer = randf_range(wander_wait * 0.7, wander_wait * 1.3)
		_set_state(State.IDLE)
		return

	# เดินไปทาง last_known_pos ถ้ามี แต่ผสมกับการสุ่มเล็กน้อย
	if _has_last_known:
		var to_target := (_last_known_pos - global_position)
		to_target.y = 0.0
		if to_target.length() > 2.0:
			_move_dir = to_target.normalized()
		else:
			# ถึงจุดหมายแล้ว ลืมตำแหน่ง
			_has_last_known = false
			_pick_wander_dir()

	# เลี้ยวหลบกำแพงตามแนวทางเดิน
	var steered := _steer_around_wall(_move_dir)
	# ถ้าข้างหน้าชนกำแพงตันจริงๆ (ทิศทาง steered แตกต่างจากเดิมมาก หรือไม่มีทางไปข้างหน้า)
	if _wall_ahead_dir(_move_dir) and _move_dir.dot(steered) < 0.3:
		_pick_wander_dir()
	else:
		_move_dir = steered

	# ถ้าตัวเบียดกำแพง ให้ slide ตามแนวผนัง
	if is_on_wall():
		var n := get_wall_normal()
		var slide_dir := _move_dir.slide(n)
		slide_dir.y = 0.0
		if slide_dir.length() > 0.1:
			_move_dir = slide_dir.normalized()

	velocity.x = _move_dir.x * patrol_speed
	velocity.z = _move_dir.z * patrol_speed
	_face_velocity()

func _tick_investigate() -> void:
	# เดินตรงไปตำแหน่งที่ได้ยินเสียง
	if not _has_last_known:
		_set_state(State.PATROL)
		return
	var to_target := (_last_known_pos - global_position)
	to_target.y = 0.0
	if to_target.length() < 1.5:
		_has_last_known = false
		_set_state(State.IDLE)
		return
	var dir := to_target.normalized()
	dir = _steer_around_wall(dir)
	velocity.x = dir.x * patrol_speed * 1.2
	velocity.z = dir.z * patrol_speed * 1.2
	_move_dir = dir
	_face_velocity()

func _tick_chase() -> void:
	if _player == null:
		_set_state(State.PATROL)
		return

	var dist := global_position.distance_to(_player.global_position)

	# โจมตีทันทีถ้าถึงระยะ (โจมตีไม่ได้ถ้า player ซ่อนตัวอยู่ในกล่อง)
	var is_player_hidden: bool = _player.has_method("is_hidden") and _player.is_hidden()
	if not is_player_hidden and dist <= attack_range and _attack_timer <= 0.0:
		_set_state(State.ATTACK)
		return

	# จัดการการคงสถานะการไล่ล่า (Chase persistence) ไม่ให้หยุดชะงักกลางคัน
	var delta := get_physics_process_delta_time()
	if _can_see_player or _can_hear_player:
		_chase_persist_timer = 3.0
		_last_known_pos = _player.global_position
		_has_last_known = true
	else:
		_chase_persist_timer -= delta
		if is_player_hidden or dist > lose_range or _chase_persist_timer <= 0.0:
			if _has_last_known:
				_set_state(State.INVESTIGATE)
			else:
				_set_state(State.PATROL)
			return

	# ไล่ตรงๆ — ถ้าเห็นหรือได้ยิน ใช้ตำแหน่งจริง / ถ้าไม่เห็นใช้ last_known_pos
	var target := _player.global_position if (_can_see_player or _can_hear_player) \
				  else _last_known_pos
	var desired := (target - global_position)
	desired.y = 0.0
	desired = desired.normalized()

	var dir := desired

	# เมื่อเข้าใกล้ผู้เล่น (< 4.0 ม.) มุ่งตรงเข้าหาเลย ไม่ต้องเลี้ยวหลบหรือสะบัดหนี และหันหน้าเข้าหาผู้เล่นตรงๆ
	if dist <= 4.0:
		dir = desired
		_stuck_dodge_timer = 0.0
		if desired.length() > 0.01:
			look_at(global_position - desired, Vector3.UP)
	elif _stuck_dodge_timer > 0.0:
		_stuck_dodge_timer -= delta
		dir = _stuck_dodge_dir
		_face_velocity()
	else:
		dir = _steer_around_wall(desired)
		if is_on_wall():
			var n := get_wall_normal()
			var slide_dir := desired.slide(n)
			slide_dir.y = 0.0
			if slide_dir.length() > 0.1:
				dir = slide_dir.normalized()

		_stuck_timer -= delta
		if _stuck_timer <= 0.0:
			if global_position.distance_to(_last_pos) < STUCK_DIST_THRESHOLD:
				var turn_angle := deg_to_rad(randf_range(60.0, 120.0)) * (1.0 if randf() > 0.5 else -1.0)
				_stuck_dodge_dir = _steer_around_wall(desired.rotated(Vector3.UP, turn_angle))
				_stuck_dodge_timer = 0.5
				dir = _stuck_dodge_dir
			_last_pos = global_position
			_stuck_timer = STUCK_CHECK_INTERVAL
		_face_velocity()

	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed
	_move_dir = dir

func _tick_attack() -> void:
	var delta := get_physics_process_delta_time()
	_attack_duration -= delta

	if _player and not (_player.has_method("is_hidden") and _player.is_hidden()):
		var to_p := (_player.global_position - global_position)
		to_p.y = 0.0
		var p_dist := to_p.length()
		if p_dist > 0.05:
			look_at(global_position - to_p.normalized(), Vector3.UP)

		# พุ่งตัวชาร์จเข้าใส่ผู้เล่นเต็มแรง (Lunge forward) เพื่อไม่ให้ผู้เล่นถอยหลังหนีได้
		if p_dist > 0.6:
			velocity.x = to_p.normalized().x * (chase_speed * 1.05)
			velocity.z = to_p.normalized().z * (chase_speed * 1.05)
		else:
			velocity.x = 0.0
			velocity.z = 0.0

		# เช็คการโจมตีโดนทันที ไม่รอ timer!
		if not _attack_has_hit and p_dist <= attack_range * 1.4:
			_deal_damage()
			_attack_has_hit = true
	else:
		velocity.x = 0.0
		velocity.z = 0.0

## ===================== Transition =====================
func _set_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.IDLE:
			_wander_timer = randf_range(wander_wait * 0.7, wander_wait * 1.3)
			_play_anim_loop(ANIM_IDLE)
			_play_loop(sfx_idle)
		State.PATROL:
			_play_anim_loop(ANIM_WALK)
			_play_loop(sfx_footstep)
		State.INVESTIGATE:
			_play_anim_loop(ANIM_WALK)
			_play_loop(sfx_footstep)
		State.CHASE:
			_last_pos = global_position
			_stuck_timer = STUCK_CHECK_INTERVAL
			_stuck_dodge_timer = 0.0
			_chase_persist_timer = 3.0
			_play_anim_loop(ANIM_RUN)
			_play_loop(sfx_chase)
		State.ATTACK:
			_attack_timer = attack_cooldown
			_attack_has_hit = false
			_attack_duration = 0.45
			_play_anim(ANIM_ATTACK)
			_play_oneshot(sfx_attack)
			if _player:
				var to_p := (_player.global_position - global_position)
				to_p.y = 0.0
				if to_p.length() > 0.05:
					look_at(global_position - to_p.normalized(), Vector3.UP)
				if to_p.length() <= attack_range * 1.4:
					_deal_damage()
					_attack_has_hit = true
		State.SCREAM:
			_scream_timer = 0.35
			_scream_cooldown = 7.0
			velocity.x = 0.0
			velocity.z = 0.0
			_play_anim(ANIM_SCREAM)
			_play_oneshot(sfx_detect)
			_play_oneshot(sfx_scream)
			if _player:
				var to_p := (_player.global_position - global_position)
				to_p.y = 0.0
				if to_p.length() > 0.05:
					look_at(global_position - to_p.normalized(), Vector3.UP)
		State.WALL_SLAM:
			velocity.x = 0.0
			velocity.z = 0.0
			_play_anim(ANIM_SLAM)
			_play_oneshot(sfx_wall_slam)

## ===================== Animation Signal =====================
func _on_animation_finished(anim_name: String) -> void:
	match _state:
		State.SCREAM:
			var is_player_hidden: bool = _player and _player.has_method("is_hidden") and _player.is_hidden()
			if is_player_hidden:
				_set_state(State.INVESTIGATE)
			else:
				_set_state(State.CHASE)
		State.ATTACK:
			var dist := global_position.distance_to(_player.global_position) if _player else 999.0
			var is_player_hidden: bool = _player and _player.has_method("is_hidden") and _player.is_hidden()
			if not is_player_hidden and not _player.get("is_dead"):
				if dist <= attack_range and _attack_timer <= 0.0:
					_set_state(State.ATTACK)
				else:
					_set_state(State.CHASE)
			else:
				_set_state(State.IDLE)
		State.WALL_SLAM:
			_set_state(State.PATROL)

## ===================== Helpers =====================
func _probe_distance(dir: Vector3, max_dist: float = 20.0) -> float:
	if dir.length() < 0.01: return 0.0
	var space := get_world_3d().direct_space_state
	var from  := global_position + Vector3(0, 0.8, 0)
	var to    := from + dir.normalized() * max_dist
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [self])
	var hit   := space.intersect_ray(query)
	if not hit.is_empty() and hit.get("collider") != _player:
		return from.distance_to(hit.position)
	return max_dist

func _pick_wander_dir() -> void:
	# ถ้ามี last_known_pos (ได้ยินเสียง) ให้มุ่งไปทางนั้น
	if _has_last_known and randf() < 0.7:
		var toward := (_last_known_pos - global_position)
		toward.y = 0.0
		if toward.length() > 1.5 and not _wall_ahead_dir(toward.normalized()):
			_move_dir = toward.normalized()
			_last_wander_dir = _move_dir
			_wander_timer = randf_range(wander_duration * 0.8, wander_duration * 1.4)
			return

	# ยิง Raycast 12 ทิศทางรอบตัว 360° เพื่อหาทางเดิน/โถงที่ลึกและเปิดโล่งที่สุดในเขาวงกต
	var best_dirs: Array[Vector3] = []
	var best_scores: Array[float] = []

	for i in 12:
		var rad := i * (TAU / 12.0)
		var test_dir := Vector3(cos(rad), 0.0, sin(rad)).normalized()
		var open_dist := _probe_distance(test_dir, 20.0)

		# ถ้าชนกำแพงทันที (< 1.5m) ตัดทิ้ง
		if open_dist < 1.5:
			continue

		var score := open_dist
		# ป้องกันไม่ให้เดินกลับหลัง 180° ซ้ำทางเดิม (ลดโอกาสเดินวนอยู่จุดเดิม)
		if _last_wander_dir != Vector3.ZERO:
			var dot := test_dir.dot(_last_wander_dir)
			if dot < -0.3:
				score *= 0.1  # ลงโทษการเลี้ยวกลับหลัง จะเลือกก็ต่อเมื่อเป็นทางตัน
			elif dot > 0.4:
				score *= 1.4  # ให้คะแนนสูงกับทิศที่เดินตรงไปข้างหน้าต่อ

		best_dirs.append(test_dir)
		best_scores.append(score)

	if best_dirs.size() > 0:
		# สุ่มแบบถ่วงน้ำหนัก (Weighted random) เลี้ยวเข้าทางที่เปิดโล่ง
		var total_score := 0.0
		for s in best_scores:
			total_score += s

		var r := randf() * total_score
		var accum := 0.0
		var chosen := best_dirs[0]
		for idx in best_dirs.size():
			accum += best_scores[idx]
			if r <= accum:
				chosen = best_dirs[idx]
				break

		_move_dir = chosen
		_last_wander_dir = chosen
		# ระยะเวลาเดิน: ถ้าเป็นทางยาว ให้เดินยาวขึ้น ไม่หยุดชะงักบ่อย
		var chosen_dist := _probe_distance(_move_dir, 20.0)
		_wander_timer = clamp(chosen_dist / patrol_speed + randf_range(1.5, 3.0), wander_duration * 0.8, wander_duration * 1.8)
	else:
		# ถ้าติดมุมอับจริงๆ ให้กลับหลังหันทิศตรงข้าม
		_move_dir = -_last_wander_dir if _last_wander_dir != Vector3.ZERO else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_last_wander_dir = _move_dir
		_wander_timer = 2.5

## หาทิศที่ไม่ชนกำแพง โดยลอง rotate หลายๆ องศาทั้งซ้ายและขวา
func _steer_around_wall(desired_dir: Vector3) -> Vector3:
	if not _wall_ahead_dir(desired_dir):
		return desired_dir  # ทิศที่ต้องการว่างอยู่

	# ลองหมุนทีละมุม ซ้าย/ขวา (15°, 30°, 45°, 60°, 75°, 90°, 110°, 135°)
	var test_angles := [15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 110.0, 135.0]
	for deg in test_angles:
		var rad := deg_to_rad(deg)
		var left  := desired_dir.rotated(Vector3.UP,  rad)
		var right := desired_dir.rotated(Vector3.UP, -rad)
		if not _wall_ahead_dir(left):  return left
		if not _wall_ahead_dir(right): return right

	# ถ้าทุกทิศรอบหน้าชนหมด ให้เลี้ยวฉาก 90°
	return desired_dir.rotated(Vector3.UP, PI * 0.5)

func _wall_ahead() -> bool:
	if _move_dir.length() > 0.1:
		return _wall_ahead_dir(_move_dir)
	return _wall_ahead_dir(global_transform.basis.z)

func _wall_ahead_dir(dir: Vector3) -> bool:
	if dir.length() < 0.01: return false
	var space := get_world_3d().direct_space_state
	var from  := global_position + Vector3(0, 0.5, 0)
	var to    := from + dir.normalized() * wall_probe_dist
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [self])
	var hit   := space.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") != _player

func _face_velocity() -> void:
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.1:
		# look_at ใช้ -Z เป็น forward แต่ model หน้าไปทาง +Z
		# ดังนั้นให้ look_at ไปทางตรงข้าม (global_position - flat)
		look_at(global_position - flat, Vector3.UP)

## เล่น animation แบบ loop (เดิน/วิ่ง/ยืน)
func _play_anim_loop(anim_name: String) -> void:
	if not (_anim and _anim.has_animation(anim_name)):
		return
	var anim := _anim.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	if _anim.current_animation != anim_name:
		_anim.play(anim_name)

## เล่น animation ครั้งเดียว (โจมตี/กรีดร้อง/ชนกำแพง)
func _play_anim(anim_name: String) -> void:
	if not (_anim and _anim.has_animation(anim_name)):
		return
	var anim := _anim.get_animation(anim_name)
	if anim:
		anim.loop_mode = Animation.LOOP_NONE
	_anim.stop()
	_anim.play(anim_name)

func _play_loop(stream: AudioStream) -> void:
	if _audio_loop == null: return
	if stream == null: _audio_loop.stop(); return
	if _audio_loop.stream == stream and _audio_loop.playing: return
	_audio_loop.stream = stream
	_audio_loop.play()

func _play_oneshot(stream: AudioStream) -> void:
	if _audio_oneshot == null or stream == null: return
	_audio_oneshot.stream = stream
	_audio_oneshot.play()

func _deal_damage() -> void:
	if _player == null: return
	if _player.has_method("is_hidden") and _player.is_hidden(): return
	if _player.get("is_dead"): return
	if _player.has_method("take_damage"):
		_player.take_damage(damage)

func trigger_wall_slam() -> void:
	_set_state(State.WALL_SLAM)

## ===================== Noise Detection (from Can) =====================
## เรียกโดย CanSpawner เมื่อกระป๋องกระทบพื้น/กำแพง
func hear_noise(noise_pos: Vector3, noise_radius: float) -> void:
	var dist := global_position.distance_to(noise_pos)
	if dist > noise_radius:
		return  # ผีอยู่ไกลเกิน ไม่ได้ยิน

	# เสียงไม่ทะลุกำแพง: ถ้ามีกำแพงกั้นระหว่างจุดเกิดเสียงกับผี ผีจะไม่ได้ยินเสียง
	if _is_sound_blocked_by_wall(noise_pos, global_position):
		return

	# หันหน้าขวับไปหาทิศทางของเสียงทันที
	var to_noise := (noise_pos - global_position)
	to_noise.y = 0.0
	if to_noise.length() > 0.1:
		_move_dir = to_noise.normalized()
		var look_target := global_position + _move_dir
		look_at(Vector3(look_target.x, global_position.y, look_target.z), Vector3.UP)

	# ตั้ง last_known_pos ไปที่จุดที่เกิดเสียง
	_last_known_pos = noise_pos
	_has_last_known = true

	# Alert แบบเดียวกับที่ได้ยินเสียงคน (กรีดร้อง/คำรามเตือนภัย แล้วสปรินต์พุ่งไปดูทันที)
	_set_state(State.SCREAM)

## ===================== Wall & Sound Occlusion =====================
## ตรวจสอบว่ามีสิ่งกีดขวาง/กำแพงกั้นระหว่างจุด 2 จุดหรือไม่
func _is_sound_blocked_by_wall(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from_h := from_pos + Vector3(0, 0.8, 0)
	var to_h   := to_pos + Vector3(0, 0.8, 0)
	var query := PhysicsRayQueryParameters3D.create(from_h, to_h, collision_mask, [self])
	var result := space.intersect_ray(query)
	if result.is_empty():
		return false
	var col: Node = result.get("collider") as Node
	if col == null or col == self:
		return false
	if _player != null and col == _player:
		return false
	# ผีตัวอื่น กระป๋อง หรือกล่อง ไม่ใช่กำแพงท่อระบายน้ำ
	if col.is_in_group("phee_tor") or col.is_in_group("can") or col.is_in_group("hiding_box"):
		return false
	var parent: Node = col.get_parent()
	if parent and (parent.is_in_group("phee_tor") or parent.is_in_group("can") or parent.is_in_group("hiding_box")):
		return false
	return true

## ลดทอนเสียงของผี (Audio Occlusion) เมื่อมีกำแพงกั้นไม่ให้เสียงทะลุมาถึงผู้เล่นเต็มๆ
func _update_audio_occlusion() -> void:
	if _player == null:
		return
	var is_blocked := _is_sound_blocked_by_wall(global_position, _player.global_position)
	if is_blocked:
		# มีกำแพงกั้น: ลดระดับเสียงลง 22 dB (เสียงอู้อี้/ไม่ทะลุกำแพง)
		if _audio_loop:
			_audio_loop.volume_db = _base_loop_volume - 22.0
		if _audio_oneshot:
			_audio_oneshot.volume_db = _base_oneshot_volume - 18.0
	else:
		if _audio_loop:
			_audio_loop.volume_db = _base_loop_volume
		if _audio_oneshot:
			_audio_oneshot.volume_db = _base_oneshot_volume
