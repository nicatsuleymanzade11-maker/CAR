extends Camera3D

@export var follow_speed = 10.0
@export var rotate_speed = 8.0

@onready var target_node = get_parent()
var position_offset : Vector3

func _ready():
	position_offset = position
	set_as_top_level(true)

func _physics_process(delta):
	if not target_node:
		return
		
	var target_transform = target_node.global_transform
	var target_position = target_transform.origin + (target_transform.basis * position_offset)
	
	global_transform.origin = global_transform.origin.lerp(target_position, delta * follow_speed)
	
	var current_quat = global_transform.basis.get_rotation_quaternion()
	var target_quat = target_transform.basis.get_rotation_quaternion()
	global_transform.basis = Basis(current_quat.slerp(target_quat, delta * rotate_speed))
