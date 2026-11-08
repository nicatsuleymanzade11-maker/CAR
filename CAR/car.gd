extends RigidBody3D

# ============================================
# CAR TUNING (BALANCED ARCADE DRIFT)
# ============================================
@export_group("Engine & Brakes")
@export var engine_power: float = 95.0
@export var brake_power: float = 70.0
@export var reverse_power: float = 45.0
@export var steering_speed: float = 4.0
@export var rolling_resistance: float = 0.8

@export_group("Realistic Engine Simulation")
@export var engine_spool_under_load: float = 1.0  # Slow RPM buildup when driving normally
@export var engine_free_rev: float = 4.0          # Fast RPM buildup when handbraking (neutral/clutch in)
@export var wheelspin_threshold: float = 0.8      # How high the RPM needs to be to peel out on launch

@export_group("Drift & Traction")
@export var normal_grip: float = 14.0
@export var drift_grip: float = 1.5         
@export var grip_recovery_speed: float = 6.0
@export var handbrake_drag: float = 6.0   

@export_group("Physics Stability")
@export var max_steer_angle: float = 0.6
@export var steer_speed: float = 5.0
@export var counter_steer_factor: float = 1.4
@export var angular_damping_normal: float = 3.0
@export var angular_damping_drift: float = 0.8  
@export var linear_damping_base: float = 0.5
@export var air_resistance: float = 0.02

@export_group("Visual Lean")
@export var tilt_amount: float = 0.12
@export var pitch_amount: float = 0.05

@export_group("Wheel References")
@export var front_left_wheel: Node3D
@export var front_right_wheel: Node3D
@export var rear_left_wheel: Node3D
@export var rear_right_wheel: Node3D

# ============================================
# INTERNAL STATE
# ============================================
var current_steer: float = 0.0
var speed: float = 0.0
var local_velocity: Vector3 = Vector3.ZERO
var drift_factor: float = 0.0
var is_handbraking: bool = false

# Simulates Engine RPM (0.0 = idle, 1.0 = redline)
var simulated_rpm: float = 0.0

var wheels: Array[Node3D] = []
var wheel_initial_bases: Array[Basis] = [] 
var wheel_roll: float = 0.0 

func _ready():
	wheels = [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]
	
	var valid_wheels: Array[Node3D] = []
	for w in wheels:
		if w != null:
			valid_wheels.append(w)
			wheel_initial_bases.append(w.transform.basis)
	wheels = valid_wheels
	
	contact_monitor = true
	max_contacts_reported = 4
	linear_damp = linear_damping_base
	angular_damp = angular_damping_normal

func _physics_process(delta):
	_calculate_local_velocity()
	_gather_input(delta)
	_apply_engine_forces(delta)
	_apply_lateral_grip()
	_apply_steering_and_drift()
	_apply_stability()
	_update_visuals(delta)
	_animate_wheels(delta)

func _calculate_local_velocity():
	local_velocity = global_transform.basis.inverse() * linear_velocity
	speed = linear_velocity.length()

func _gather_input(delta):
	var steer_input = Input.get_axis("ui_left", "ui_right")
	is_handbraking = Input.is_action_pressed("ui_select")
	
	var target_steer = steer_input * max_steer_angle
	current_steer = move_toward(current_steer, target_steer, steer_speed * delta)
	
	# Handbrake drifting logic
	if is_handbraking and speed > 2.0:
		drift_factor = move_toward(drift_factor, 1.0, delta * 6.0)
	elif not is_handbraking and simulated_rpm > wheelspin_threshold and speed < 5.0 and Input.get_axis("ui_down", "ui_up") > 0.1:
		# REALISM TWEAK: Dumping the clutch at high RPM from a standstill breaks traction (Burnout!)
		drift_factor = move_toward(drift_factor, 1.0, delta * 8.0)
	else:
		drift_factor = move_toward(drift_factor, 0.0, delta * grip_recovery_speed)
	
	angular_damp = lerp(angular_damping_normal, angular_damping_drift, drift_factor)

func _apply_engine_forces(delta):
	var raw_throttle = Input.get_axis("ui_down", "ui_up")
	var forward_speed = -local_velocity.z
	
	# ==========================================
	# 1. REALISTIC RPM SIMULATION
	# ==========================================
	if raw_throttle > 0.1:
		if is_handbraking:
			# Engine free-revs quickly because there is no load on the wheels
			simulated_rpm = move_toward(simulated_rpm, 1.0, engine_free_rev * delta)
		else:
			# Engine struggles to push the heavy car, so RPM builds slowly
			simulated_rpm = move_toward(simulated_rpm, 1.0, engine_spool_under_load * delta)
	else:
		# Dropping the throttle drops the RPM fast
		simulated_rpm = move_toward(simulated_rpm, 0.0, engine_free_rev * delta)

	# ==========================================
	# 2. APPLY ENGINE FORCES
	# ==========================================
	if not is_handbraking:
		if raw_throttle > 0.1:
			if forward_speed < -0.5:
				# Brakes
				apply_central_force(-linear_velocity.normalized() * brake_power * raw_throttle)
			else:
				# Acceleration is now tied directly to the simulated RPM
				apply_central_force(-global_transform.basis.z * engine_power * simulated_rpm)
				
		elif raw_throttle < -0.1:
			if forward_speed > 0.5:
				# Brakes
				apply_central_force(-linear_velocity.normalized() * brake_power * abs(raw_throttle))
			else:
				# Reverse
				apply_central_force(global_transform.basis.z * reverse_power * abs(raw_throttle))
	
	# ==========================================
	# 3. DRAG & RESISTANCE
	# ==========================================
	if abs(raw_throttle) < 0.1 and speed > 0.1:
		apply_central_force(-linear_velocity.normalized() * rolling_resistance * mass)
	
	if speed > 0.1:
		apply_central_force(-linear_velocity * speed * air_resistance * mass)
	
	if is_handbraking and speed > 0.1:
		apply_central_force(-linear_velocity.normalized() * handbrake_drag * mass)

func _apply_lateral_grip():
	var grip = lerp(normal_grip, drift_grip, drift_factor)
	var lateral_vel = local_velocity.x
	var lateral_force = -lateral_vel * grip * mass
	apply_central_force(global_transform.basis.x * lateral_force)

func _apply_steering_and_drift():
	if speed < 0.5:
		return
	
	var steer_effectiveness = lerp(1.0, 0.5, clamp(speed / 40.0, 0.0, 1.0))
	var forward_speed = -local_velocity.z
	var move_dir = 1.0 if forward_speed >= 0 else -1.0
	
	var counter_steer = 0.0
	if drift_factor > 0.2 and speed > 3.0:
		var slide_dir = sign(local_velocity.x)
		var steer_dir = sign(current_steer)
		if slide_dir != 0 and steer_dir != 0 and slide_dir != steer_dir:
			counter_steer = counter_steer_factor * drift_factor
	
	var turn_torque = -current_steer * speed * steering_speed * steer_effectiveness * move_dir
	turn_torque += counter_steer * speed * 0.8 * move_dir
	
	apply_torque(Vector3.UP * turn_torque)
	
	if is_handbraking and speed > 3.0 and abs(current_steer) > 0.05:
		var drift_kick = -current_steer * speed * 2.0 * move_dir
		apply_torque(Vector3.UP * drift_kick)

func _apply_stability():
	var steer_input = abs(Input.get_axis("ui_left", "ui_right"))
	var angular_y = angular_velocity.y
	
	if is_handbraking:
		apply_torque(Vector3.UP * -angular_y * 1.0 * mass)
	elif steer_input < 0.1 and speed > 1.0:
		apply_torque(Vector3.UP * -angular_y * 2.0 * mass)
	
	if global_transform.basis.y.dot(Vector3.UP) < 0.3:
		var right = global_transform.basis.x
		apply_torque(right * 10.0 * mass)

func _update_visuals(delta):
	var target_tilt = Vector3.ZERO
	var steer_input = Input.get_axis("ui_left", "ui_right")
	var throttle = Input.get_axis("ui_down", "ui_up")
	
	target_tilt.z = -steer_input * tilt_amount * clamp(speed / 30.0, 0.0, 1.0)
	target_tilt.x = throttle * pitch_amount
	
	if drift_factor > 0.2:
		target_tilt.z += sign(steer_input) * tilt_amount * 1.0 * drift_factor
	
	var hull = get_node_or_null("Hull")
	if hull:
		hull.rotation.x = lerp(hull.rotation.x, target_tilt.x, delta * 5.0)
		hull.rotation.z = lerp(hull.rotation.z, target_tilt.z, delta * 5.0)

func _animate_wheels(delta):
	if wheels.is_empty():
		return
	
	var forward_speed = -local_velocity.z
	var roll_speed = forward_speed * delta * 2.0
	
	wheel_roll += roll_speed
	wheel_roll = wrapf(wheel_roll, -PI, PI)
	
	for i in wheels.size():
		var wheel = wheels[i]
		
		wheel.transform.basis = wheel_initial_bases[i]
		
		if wheel == front_left_wheel or wheel == front_right_wheel:
			wheel.rotate_y(-current_steer)
		
		var current_wheel_roll = wheel_roll
		if wheel == front_right_wheel or wheel == rear_right_wheel:
			current_wheel_roll = -wheel_roll
			
		wheel.rotate_object_local(Vector3.RIGHT, current_wheel_roll)
