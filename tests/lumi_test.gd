extends SceneTree
## Проверки доработок Lumi: безопасный возврат из воды, восстановление камеры после
## фото/обзора и сложность (масло, урон, волны, рассудок, достижимая смерть).
const BAL = preload("res://scripts/balance.gd")
var game: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func physics(count: int) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hours_per_second = 0
	game.start_shift()
	await physics(60)

	# ---------- безопасный возврат на последнюю твёрдую землю
	var spot := Vector3(-3, 1.4, 3)
	game.player.position = spot
	game.player.velocity = Vector3.ZERO
	await physics(60)
	check(game.last_safe_position.distance_to(game.player.position) < 1.0, "Solid ground under the keeper is remembered as the last safe point")
	var remembered: Vector3 = game.last_safe_position
	var before: float = game.health
	game.player.position = Vector3(50, -3, 50)
	game.player.velocity = Vector3.ZERO
	await physics(90)
	check(game.player.position.distance_to(remembered) < 1.2, "Falling into the sea returns the keeper to the last safe ground, not to the hut")
	check(game.player.position.distance_to(Vector3(3, 1, 4)) > 3.0, "Respawn is not the cabin spawn when a closer safe point is known")
	check(is_equal_approx(game.health, before - BAL.FALL_DAMAGE), "Fall costs exactly FALL_DAMAGE once")
	check(game.respawn_grace > 0, "Island event timers get a short grace period after the rescue")
	var rails: Node = game.world.get_node_or_null("NorthernCoast/ShipGangplank/GangplankRails")
	check(rails != null and rails.get_child_count() >= 2, "Gangplank gets invisible rails")

	# ---------- камера после фото и обзора
	game.overview = true
	game.camera_zoom = 78.0
	game.photo.has_camera = true
	game.photo.open()
	check(game.photo.active and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Photo mode switches to the perspective camera")
	game.photo.close()
	await process_frame
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Closing photo mode restores the orthographic projection")
	check(not game.overview, "Closing photo mode leaves the island overview")
	check(game.camera_zoom >= 18 and game.camera_zoom <= 38 and game.camera.size <= 38.5, "Zoom is clamped back to 18–38 after a photo")
	game.overview = true
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var zoom_before: float = game.target_zoom
	game._unhandled_input(wheel)
	check(not game.overview and game.target_zoom < zoom_before or (not game.overview and game.target_zoom == 18), "Mouse wheel exits overview and zooms in instead of being ignored")
	game.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game.update_camera(0.0)
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "A stray perspective projection is repaired by the camera update")

	# ---------- сложность
	check(BAL.wave_size(1, 1, 0.0) == 1, "First wave of the night is a single shadow")
	check(BAL.wave_size(8, 3, 1.0) > 1, "Later waves grow")
	check(BAL.wave_interval(10, 1.0) < BAL.wave_interval(1, 0.0), "Waves come faster deeper into the campaign")
	check(BAL.shadow_damage(5, false) >= 15 and BAL.shadow_damage(5, true) > BAL.shadow_damage(5, false), "Shadow damage comes from the balance file and drowned hit harder")
	game.player.position = spot
	game.hour = 22.0
	game.player.lantern_on = true
	game.lantern_oil = 1.0
	await physics(150)
	check(not game.player.lantern_on and game.lantern_oil <= 0, "Lantern oil drains at night and the lantern goes out")
	game.toggle_lantern()
	check(not game.player.lantern_on, "An empty lantern cannot be relit outside")
	# ---------- хоррор-режиссёр
	var sc: Node = game.scares
	game.lantern_oil = 80.0
	game.player.lantern_on = true
	sc.fire("figure")
	check(is_instance_valid(sc.figure), "Figure scare puts a silhouette in front of the keeper")
	sc.queue("flicker")
	check(not "flicker" in sc.eligible(), "A scare type is on cooldown right after it fires")
	check(sc.quiet == 0.0, "Any scare resets the quiet timer so scares cannot chain")
	var fear_before: float = sc.fear
	sc.fire("slam")
	check(sc.fear >= fear_before, "Door slam jolts the fear level")
	sc.fire("radio")
	sc.fire("breath")
	game.sanity = 20.0
	sc.fire("lunge")
	check(is_instance_valid(sc.lunger), "Low sanity enables the phantom lunge")
	await physics(120)
	check(not game.finished, "Scares never kill the keeper outright")
	sc.reset()
	game.player.lantern_on = false
	game.lantern_oil = 0.0
	game.sanity = 100.0
	var sanity_before: float = game.sanity
	await physics(60)
	check(game.sanity < sanity_before, "Sanity drains at night in the dark")
	game.sanity = 0
	game.health = 2.0
	game.clear_enemies()
	await physics(200)
	check(game.finished and not game.last_run_won, "Death is reachable: a broken mind in the dark ends the shift")
	print("RESULT: ", checks - failures, "/", checks, " lumi checks passed")
	game.queue_free()
	await create_timer(0.1).timeout
	quit(0 if failures == 0 else 1)
