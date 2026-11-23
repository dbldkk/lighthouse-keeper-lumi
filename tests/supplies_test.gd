extends SceneTree
## Скудные ресурсы: запас масла, ракетница, тайники, обмен топлива у хижины.
var game: Node
var sp: Node3D
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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_supplies.json"
	game.start_shift()
	sp = game.supplies
	await frames(2)
	check(sp.flares == sp.FLARES_START and is_equal_approx(sp.oil_reserve, sp.OIL_START), "Shift starts with one flare and a small oil reserve")
	check(sp.caches.size() >= 2 and sp.caches_day == 1, "Daily caches are placed")
	var ok_ground := true
	for c in sp.caches:
		ok_ground = ok_ground and game.night_raids.ground_at(c.at) != null
	check(ok_ground, "Caches lie on walkable ground")

	# масло из запаса
	game.enter_building("cabin")
	game.lantern_oil = 0
	sp.oil_reserve = 30
	for i in 20:
		game.update_lantern_oil(1.0)
	check(is_equal_approx(game.lantern_oil, 30.0) and sp.oil_reserve <= 0.01, "Indoors the lantern refills only from the reserve")
	game.update_lantern_oil(1.0)
	check(is_equal_approx(game.lantern_oil, 30.0), "With an empty reserve there is no refill")
	game.exit_building()

	# обмен
	game.player.global_position = sp.stations[0].at + Vector3(.5, .4, 0)
	game.inventory.fuel = 0
	check(sp.near().get("id", "") == "oil_barrel" and not sp.trade("oil_barrel"), "Oil trade needs fuel")
	game.inventory.fuel = 2
	check(sp.interact() and game.inventory.fuel == 1 and sp.oil_reserve >= sp.OIL_PER_FUEL - .1, "1 fuel becomes oil in the reserve")
	sp.flares = 0
	game.expedition.state.scrap = 1
	check(sp.trade("flare_crate") and sp.flares == 1 and game.inventory.fuel == 0 and int(game.expedition.state.scrap) == 0, "Fuel + scrap become a flare")
	check(not sp.trade("flare_crate"), "No more flares without materials")

	# тайник
	var c: Dictionary = sp.caches[0]
	c.loot = "flare"
	game.player.global_position = c.at + Vector3(.4, .4, 0)
	var before: int = sp.flares
	check(sp.near().get("kind", "") == "cache" and sp.interact() and sp.flares == before + 1 and c.taken, "Opening a cache gives its loot once")
	check(not sp.interact() or sp.near().get("index", -1) != 0, "An opened cache stays empty")

	# ракета отгоняет охотника
	game.day = 3
	game.campaign.state.day = 3
	game.campaign.state.night = true
	await frames(2)
	var h: Node3D = game.hunter
	check(h.active, "Hunter is out")
	game.player.global_position = Vector3(2, 1.2, 6)
	h.body.global_position = Vector3(2, 1, 14)
	h._set_state("chase")
	var shots: int = sp.flares
	check(sp.fire_flare() and sp.flares == shots - 1 and sp.flare_active(), "X fires a flare")
	check(h.state == "flee", "The flare drives the hunter away")
	game.spawn_shadow(Vector3(4, 1.3, 7))
	var shadow: Node = game.enemies.back()
	sp.flares = 1
	sp.fire_flare()
	check(shadow.is_dissolving(), "A flare burns nearby shadows")
	sp.flares = 0
	check(not sp.fire_flare(), "No flare left — nothing happens")
	game.campaign.state.night = false

	# новый день — новые тайники
	game.day = 4
	game.campaign.state.day = 4
	await frames(2)
	check(sp.caches_day == 4 and not sp.caches[0].taken, "Next day brings new caches")
	# сохранение
	sp.oil_reserve = 123
	sp.flares = 2
	check(game.save_game(true), "Saved")
	sp.reset()
	check(game.load_game() and is_equal_approx(sp.oil_reserve, 123) and sp.flares == 2 and sp.caches_day == 4, "Reserve, flares and caches survive a reload")
	print("SUPPLIES_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
