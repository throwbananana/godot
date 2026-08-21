class_name MapGenerator
extends RefCounted

enum Biome { PLAINS_FORTRESS, DESERT_DUNES, GLACIAL_VOID }
enum Symmetry { HORIZONTAL, ROTATIONAL, ASYMMETRIC }

# Generates a valid, playable 13x13 map grid
static func generate_map(act: int = 1, symmetry: Symmetry = Symmetry.HORIZONTAL, custom_seed: int = 0) -> Array:
	var rng = RandomNumberGenerator.new()
	if custom_seed != 0:
		rng.seed = custom_seed
	else:
		rng.randomize()

	var biome = Biome.PLAINS_FORTRESS
	match act:
		1: biome = Biome.PLAINS_FORTRESS
		2: biome = Biome.DESERT_DUNES
		3: biome = Biome.GLACIAL_VOID
		_: biome = Biome.PLAINS_FORTRESS

	# Initialize empty 13x13 grid
	var grid: Array = []
	for r in range(13):
		var row: Array = []
		for c in range(13):
			row.append(0)
		grid.append(row)

	# 1. Generate Left Half (Columns 0 to 6)
	for r in range(1, 12):
		for c in range(1, 7):
			# Skip Eagle Base Sanctuary Area (r >= 10, c >= 4)
			if r >= 10 and c >= 4:
				continue
			# Skip Top Enemy Spawn Zones (r <= 1, c in [0, 1, 6])
			if r <= 1 and (c <= 1 or c == 6):
				continue

			var tile = _generate_tile_for_biome(biome, r, c, rng)
			grid[r][c] = tile

	# 2. Apply Symmetry to Right Half (Columns 7 to 12)
	if symmetry == Symmetry.HORIZONTAL:
		for r in range(13):
			for c in range(7, 13):
				var mirror_c = 12 - c
				var src_tile = grid[r][mirror_c]
				grid[r][c] = _mirror_tile_horizontal(src_tile)
	elif symmetry == Symmetry.ROTATIONAL:
		for r in range(13):
			for c in range(7, 13):
				var mirror_r = 12 - r
				var mirror_c = 12 - c
				var src_tile = grid[mirror_r][mirror_c]
				grid[r][c] = _mirror_tile_rotational(src_tile)

	# 3. Clear Critical Spawns & Corridors
	_carve_critical_paths(grid)

	# 4. Sprinkle Tactical Elements (Shield Station, Jump Pad, Wormhole)
	_sprinkle_tactical_features(grid, biome, rng)

	return grid

static func _generate_tile_for_biome(biome: Biome, r: int, c: int, rng: RandomNumberGenerator) -> int:
	var roll = rng.randf()

	match biome:
		Biome.PLAINS_FORTRESS:
			# Focus: Brick, Hard Clay, Rivers, Foliage, Conveyors, Oil Barrels, Electric Walls
			if roll < 0.32: return 0 # Empty
			elif roll < 0.48: return 1 # Brick Wall
			elif roll < 0.58: return 8 # Hard Clay Block (3HP)
			elif roll < 0.65: return 2 # Steel Wall
			elif roll < 0.72: return 3 # River Water
			elif roll < 0.78: return 4 # Foliage
			elif roll < 0.84: return 26 # Explosive Oil Barrel
			elif roll < 0.90: return 25 # Electric Wall
			elif roll < 0.95: return 18 # Conveyor UP
			else: return 21 # Conveyor RIGHT

		Biome.DESERT_DUNES:
			# Focus: Quicksand, Sand Dunes, Hard Clay, Wind Blowers, Jump Pads, Oil Barrels
			if roll < 0.30: return 0 # Empty
			elif roll < 0.45: return 6 # Quicksand Ground
			elif roll < 0.58: return 7 # Sand Dune Block
			elif roll < 0.68: return 8 # Hard Clay Block
			elif roll < 0.74: return 2 # Steel Wall
			elif roll < 0.80: return 26 # Explosive Oil Barrel
			elif roll < 0.86: return 14 # Wind Blower UP
			elif roll < 0.92: return 22 # Jump Pad
			elif roll < 0.96: return 25 # Electric Wall
			else: return 17 # Wind Blower RIGHT

		Biome.GLACIAL_VOID:
			# Focus: Glacial Ice, Wormholes, Moving Platforms, Electric Walls, Street Lamps, Shield Stations
			if roll < 0.28: return 0 # Empty
			elif roll < 0.44: return 9 # Glacial Ice
			elif roll < 0.54: return 8 # Hard Clay
			elif roll < 0.62: return 2 # Steel Wall
			elif roll < 0.70: return 25 # Electric Wall
			elif roll < 0.76: return 3 # Void River
			elif roll < 0.84: return 12 # Cosmic Wormhole
			elif roll < 0.90: return 22 # Jump Pad
			elif roll < 0.95: return 24 # Street Lamp
			else: return 10 # Moving Platform

	return 0

static func _mirror_tile_horizontal(tile: int) -> int:
	# Mirror directional tiles
	match tile:
		16: return 17 # Wind LEFT -> RIGHT
		17: return 16 # Wind RIGHT -> LEFT
		20: return 21 # Conveyor LEFT -> RIGHT
		21: return 20 # Conveyor RIGHT -> LEFT
		_: return tile

static func _mirror_tile_rotational(tile: int) -> int:
	match tile:
		14: return 15 # Wind UP -> DOWN
		15: return 14 # Wind DOWN -> UP
		16: return 17 # Wind LEFT -> RIGHT
		17: return 16 # Wind RIGHT -> LEFT
		18: return 19 # Conveyor UP -> DOWN
		19: return 18 # Conveyor DOWN -> UP
		20: return 21 # Conveyor LEFT -> RIGHT
		21: return 20 # Conveyor RIGHT -> LEFT
		_: return tile

static func _carve_critical_paths(grid: Array) -> void:
	# Keep top row and bottom row borders free
	for c in range(13):
		grid[0][c] = 0
		grid[12][c] = 0

	# Keep Enemy Spawn Tiles (Col 0, 6, 12, Row 0 & 1) completely clear
	for c in [0, 1, 5, 6, 7, 11, 12]:
		grid[0][c] = 0
		grid[1][c] = 0

	# Keep Player Spawn & Eagle Base Area Clear (Row 11 & 12, Col 4..8)
	for r in [10, 11, 12]:
		for c in [4, 5, 6, 7, 8]:
			grid[r][c] = 0

	# Keep vertical central corridor partially open (Col 6)
	for r in [2, 3, 7, 8, 9]:
		if grid[r][6] == 2 or grid[r][6] == 25: # Replace blocking steel or electric wall with empty or passable
			grid[r][6] = 0

static func _sprinkle_tactical_features(grid: Array, biome: Biome, rng: RandomNumberGenerator) -> void:
	# Place 1 or 2 Shield Stations at key tactical cross points
	var shield_candidates = [Vector2(2, 6), Vector2(10, 6), Vector2(6, 3), Vector2(6, 9)]
	shield_candidates.shuffle()
	var sc = shield_candidates[0]
	grid[int(sc.y)][int(sc.x)] = 13 # Shield Station
	grid[int(sc.y)][12 - int(sc.x)] = 13

	# Place Street Lamps at key crossroads
	grid[2][2] = 24 # Street Lamp Top-Left
	grid[2][10] = 24 # Street Lamp Top-Right
	grid[8][2] = 24 # Street Lamp Bottom-Left
	grid[8][10] = 24 # Street Lamp Bottom-Right

	# Place Tactical Biome-specific Features
	if biome == Biome.GLACIAL_VOID:
		grid[3][3] = 12 # Wormhole
		grid[3][9] = 12
		grid[9][3] = 12
		grid[9][9] = 12
		grid[6][1] = 25 # Electric Wall flank
		grid[6][11] = 25
	elif biome == Biome.DESERT_DUNES:
		grid[4][2] = 22 # Jump Pad
		grid[4][10] = 22
		grid[8][4] = 26 # Oil Barrel
		grid[8][8] = 26
		grid[6][6] = 22 # Central Jump Pad
	elif biome == Biome.PLAINS_FORTRESS:
		grid[4][3] = 26 # Oil Barrel
		grid[4][9] = 26
		grid[7][3] = 22 # Jump Pad
		grid[7][9] = 22
