extends SceneTree

# Verifies GameState.grant_star_tier_reward() -- the fix for STAR power-ups /
# the shop's star_tier item / the "depot" event's tier-up option becoming
# silent no-ops once a player picks a branch (speed/heavy/train), since
# player.gd only reads player_tier/p2_tier in the still-undecided "default"
# branch's weapon path. Once branched, the reward should redirect to a
# permanent +1 ATK instead of quietly doing nothing.

func _init() -> void:
	print("==================================================")
	print(">>> RUNNING STAR TIER REWARD TEST  <<<")
	print("==================================================")

	_test_default_branch_bumps_tier()
	_test_branched_player_redirects_to_atk()
	_test_players_are_independent()

	print("\n>>> ALL STAR TIER REWARD CHECKS PASSED! <<<")
	quit(0)

func _test_default_branch_bumps_tier() -> void:
	print("\n[STEP] Still on 'default' branch: reward bumps player_tier, capped at 3...")
	GameState.reset_campaign(1)
	assert(GameState.tank_branch == "default", "fresh campaign should start on default branch")
	assert(GameState.player_tier == 0, "fresh campaign should start at tier 0")
	var atk_before = GameState.atk_bonus

	GameState.grant_star_tier_reward(1)
	GameState.grant_star_tier_reward(1)
	GameState.grant_star_tier_reward(1)
	GameState.grant_star_tier_reward(1) # 4th call should clamp, not overflow
	assert(GameState.player_tier == 3, "player_tier should clamp at 3, got %d" % GameState.player_tier)
	assert(GameState.atk_bonus == atk_before, "default-branch reward should NOT touch atk_bonus")

	print("  [PASS] default-branch reward bumps player_tier and clamps at 3, doesn't touch atk_bonus.")

func _test_branched_player_redirects_to_atk() -> void:
	print("\n[STEP] Branch already picked: reward redirects to +1 ATK, uncapped...")
	GameState.reset_campaign(1)
	GameState.tank_branch = "speed" # simulate having picked a branch at level 2
	var tier_before = GameState.player_tier
	var atk_before = GameState.atk_bonus

	for i in range(5): # deliberately more than the old tier-3 cap
		GameState.grant_star_tier_reward(1)

	assert(GameState.player_tier == tier_before, "branched reward should NOT touch player_tier (would be a silent no-op otherwise)")
	assert(GameState.atk_bonus == atk_before + 5, "branched reward should add +1 atk_bonus per call with no cap, got %d" % GameState.atk_bonus)

	print("  [PASS] Once branched, reward redirects to uncapped +1 atk_bonus instead of a dead stat.")

func _test_players_are_independent() -> void:
	print("\n[STEP] P1/P2 branch state evaluated independently in 2P co-op...")
	GameState.reset_campaign(2)
	GameState.tank_branch = "default"
	GameState.p2_branch = "heavy" # P2 already branched, P1 still undecided
	var atk_before = GameState.atk_bonus

	GameState.grant_star_tier_reward(1) # P1: still default -> tier bump
	GameState.grant_star_tier_reward(2) # P2: branched -> atk redirect

	assert(GameState.player_tier == 1, "P1 (still default) should get a tier bump, got %d" % GameState.player_tier)
	assert(GameState.p2_tier == 0, "P2 (branched) should NOT get a tier bump")
	assert(GameState.atk_bonus == atk_before + 1, "P2 (branched) should get the +1 atk_bonus redirect")

	print("  [PASS] P1 default / P2 branched in the same 2P run each get the correct reward independently.")
