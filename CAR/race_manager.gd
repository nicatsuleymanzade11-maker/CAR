extends Node

@export_group("Race Rules")
@export var total_checkpoints: int = 3 # Change this based on how many you place
@export var total_laps: int = 3

# Dictionary to hold the progress of the player and future AI
var racer_progress: Dictionary = {}

func register_racer(racer_node: Node3D):
	racer_progress[racer_node] = {
		"current_lap": 1,
		"last_checkpoint": -1 # Starts at -1 so hitting Checkpoint 0 (Start line) counts!
	}

func racer_hit_checkpoint(racer_node: Node3D, checkpoint_id: int):
	# If this is the first time the manager sees this car, register it
	if not racer_progress.has(racer_node):
		register_racer(racer_node)
		
	var progress = racer_progress[racer_node]
	var expected_checkpoint = (progress["last_checkpoint"] + 1) % total_checkpoints
	
	# Did they hit the correct next checkpoint?
	if checkpoint_id == expected_checkpoint:
		progress["last_checkpoint"] = checkpoint_id
		print(racer_node.name, " hit checkpoint ", checkpoint_id)
		
		# Checkpoint 0 is always the Start/Finish line
		if checkpoint_id == 0:
			if progress["current_lap"] < total_laps:
				progress["current_lap"] += 1
				print(racer_node.name, " started lap ", progress["current_lap"])
			else:
				print(racer_node.name, " FINISHED THE RACE!")
