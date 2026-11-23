extends SceneTree
## Охотник: шум, свет, погоня, укрытия, задержка дыхания, отпугивание.
var game: Node
var h: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", title)
	else:
		failures += 1
		push_error("FAIL: " + title)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func night(day: int) -> void:
	game.day = day
	game.campaign.state.day = day
	game.campaign.state.night = true
	game.hour = 21

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_hunter.json"
	game.start_shift()
	h = game.hunter
	await frames(3)
	check(is_instance_valid(h) and h.spots.size() == 3, "Hunter and three hiding spots exist")
	check(not h.active, "No hunter during the day")
	night(1)
	await frames(2)
	check(not h.active, "No hunter on the tutorial night")
	night(3)
	await frames(2)
	check(h.active and h.state == "patrol", "Hunter spawns and patrols at night")
	var far: float = h.body.global_position.distance_to(game.player.global_position)
	check(far > 10, "It appears far from the keeper (%.1f m)" % far)

	# шум
	h.body.global_position = Vector3(-10, 1, 8)
	h.noise(Vector3(-4, 1, 6), .8)
	check(h.state == "investigate" and h.target.distance_to(Vector3(-4, 1, 6)) < .1, "Noise draws it to investigate")

	# свет фонаря: видит дальше
	game.lighthouse_on = false
	game.barricade_built = false
	game.player.global_position = Vector3(2, 1.2, 6)
	game.player.lantern_on = true
	h.body.global_position = Vector3(2, 1, 6 + 12)
	check(h._can_see_player(), "A lit lantern is seen from 12 m")
	game.player.lantern_on = false
	check(not h._can_see_player(), "In the dark it does not see you from 12 m")
	game.player.lantern_on = true

	# поймал
	h._set_state("chase")
	h.body.global_position = game.player.global_position + Vector3(.8, 0, 0)
	var hp: float = game.health
	var san: float = game.sanity
	h._tick_outside(.016)
	check(game.health <= hp - h.DAMAGE + .1 and game.sanity < san, "Being caught costs heavy health and sanity")
	check(h.state == "flee", "After a catch it backs off so the keeper can recover")
	game.health = 100

	# свет маяка отгоняет
	h._set_state("patrol")
	game.lighthouse_on = true
	h.body.global_position = Vector3(-9, 1, -4)
	h._tick_outside(.016)
	check(h.state == "flee", "The lit lighthouse repels it")
	game.lighthouse_on = false
	h._set_state("patrol")
	h.body.global_position = Vector3(5, 1, 10)
	check(h.repel(Vector3(5, 1, 9), 10.0) and h.state == "flee", "A flare/light burst nearby repels it")

	# укрытие: шкаф в хижине
	game.enter_building("cabin")
	await frames(2)
	var wardrobe: Dictionary = {}
	for s in h.spots:
		if s.id == "wardrobe":
			wardrobe = s
	game.player.global_position = wardrobe.at + Vector3(.3, 0, .5)
	check(not h.spot_near(game.player.global_position).is_empty(), "Wardrobe is reachable inside the cabin")
	check(h.interact() and h.hiding() and not game.player.enabled and not game.player.lantern_on, "E hides the keeper and douses the lantern")
	# охотник входит
	h.space = "cabin"
	h.room_clock = 0
	h.body.global_position = wardrobe.at + Vector3(.5, 0, .8)
	h.holding_forced = true
	h._tick_breath(.5)
	var s_before: float = game.sanity
	h._sniff_hiding()
	check(h.hiding(), "Holding breath keeps you hidden right next to it")
	h._tick_breath(1.0)
	check(game.sanity < s_before and h.breath < h.BREATH_MAX, "Holding breath drains breath and sanity")
	h.holding_forced = false
	h._tick_breath(.1)
	hp = game.health
	h.mercy_time = 0   # отдельный сценарий: передышка после прошлого броска не действует
	h._sniff_hiding()
	check(not h.hiding() and game.health < hp, "Breathing next to it gets you dragged out")
	game.health = 100
	h.space = ""

	# следует внутрь
	h.hide_in("wardrobe")
	h.leave_hiding()
	game.player.global_position = wardrobe.at + Vector3(.3, 0, .6)
	h._set_state("chase")
	h.body.global_position = game.building_interiors.exit_at("cabin") + Vector3(1, 0, 0)
	for i in 30:
		h._try_follow_inside(.1)
	check(h.space == "cabin", "If it saw you go inside, it follows through the door")
	game.exit_building()
	await frames(1)
	h._tick_room(.016)
	check(h.space == "", "It leaves the room after you")

	# дыхание кончилось — вздох
	game.enter_building("cabin")
	game.player.global_position = wardrobe.at + Vector3(.3, 0, .5)
	h.hide_in("wardrobe")
	h.space = "cabin"
	h.body.global_position = wardrobe.at + Vector3(2.5, 0, 0)
	h.holding_forced = true
	hp = game.health
	h.mercy_time = 0
	for i in 10:
		h._tick_breath(1.0)
	check(not h.hiding() and game.health < hp, "Running out of breath makes you gasp and be found")
	h.holding_forced = false
	game.health = 100
	h.space = ""
	game.exit_building()

	# рассвет
	game.campaign.state.night = false
	await frames(2)
	check(not h.active, "It leaves at dawn")
	print("HUNTER_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
