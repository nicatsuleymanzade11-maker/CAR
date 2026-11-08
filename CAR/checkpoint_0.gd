extends Area3D

@export var checkpoint_id: int = 0

func _ready():
	# Connect the signal in code so you don't have to do it manually in the editor every time
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D):
	if body.is_in_group("racer"):
		var race_manager = get_tree().get_first_node_in_group("race_manager")
		if race_manager:
			race_manager.racer_hit_checkpoint(body, checkpoint_id)
