class_name TrainFollowHelper
extends RefCounted

## Snake-style path following: a leader (player/enemy tank, or another
## TrainCarriage further up the chain) records its exact position+rotation
## every physics frame; a follower samples that recorded path at a fixed
## distance behind the leader's current position. Because the leader only
## ever moves in the 4 cardinal directions (see player.gd's input_vec /
## enemy.gd's facing_direction, both if/elif chains that pick exactly one
## axis), the follower's path is a delayed copy of an already axis-aligned
## path -- it can't cut corners diagonally the way lerp-toward-a-point does.

const MAX_HISTORY_DIST: float = 400.0 # generous headroom for a multi-carriage chain

static func record_history(positions: Array[Vector2], rotations: Array[float], pos: Vector2, rot: float) -> void:
	positions.push_back(pos)
	rotations.push_back(rot)

	var total_dist = 0.0
	var trim_to = 0
	for i in range(positions.size() - 1, 0, -1):
		total_dist += positions[i].distance_to(positions[i - 1])
		if total_dist > MAX_HISTORY_DIST:
			trim_to = i
			break
	for _i in range(trim_to):
		positions.pop_front()
		rotations.pop_front()

static func sample_at_distance(positions: Array[Vector2], rotations: Array[float], follow_distance: float) -> Dictionary:
	if positions.is_empty():
		return {}
	var accum = 0.0
	for i in range(positions.size() - 1, 0, -1):
		var seg = positions[i].distance_to(positions[i - 1])
		if accum + seg >= follow_distance:
			var t = (follow_distance - accum) / seg if seg > 0.001 else 0.0
			return {
				"position": positions[i].lerp(positions[i - 1], t),
				"rotation": lerp_angle(rotations[i], rotations[i - 1], t),
			}
		accum += seg
	return {"position": positions[0], "rotation": rotations[0]}
