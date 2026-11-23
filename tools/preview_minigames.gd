extends SceneTree
## Скриншоты отдельных мини-игр механизмов. Запуск с экраном (не --headless):
## godot --path . --script res://tools/preview_minigames.gd -- [папка]
var OUT := "res://docs/minigames/"
var game: Node
var mini: Control

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		OUT = arg.trim_suffix("/") + "/"
	call_deferred("run")

func shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT + name if OUT.begins_with("/") else ProjectSettings.globalize_path(OUT + name)
	root.get_texture().get_image().save_png(path)
	print("Captured ", path)

func station(id: String) -> Area3D:
	for item in game.stations:
		if item.station_id == id:
			return item
	return game.stations[0]

func open(id: String) -> RefCounted:
	mini.close()
	game.hud.overlay.card_time = 0
	game.hud.overlay.alert_time = 0
	game.message_time = 0
	game.radio.reset()
	mini.open_repair(station(id), id)
	return mini.sub

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT if OUT.begins_with("/") else ProjectSettings.globalize_path(OUT))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://preview_minigames.json"
	game.start_shift()
	game.hours_per_second = 0
	game.day = 6
	game.campaign.state.day = 6
	mini = game.minigames
	mini.enabled = true
	game.player.position = station("beacon").position + Vector3(0, .3, 1.2)
	await create_timer(1.0).timeout

	# генератор — маховик
	open("beacon")
	mini.hits = 1
	mini.misses = 1
	mini.needle = mini.sector - .7
	mini.clock = 2.0
	await shot("01_generator_flywheel.png")

	# проводка
	var w: RefCounted = open("sparks")
	w._choose(0)
	w._choose(w.order.find(0))
	w._choose(1)
	w.heat = .55
	w.clock = 1.0
	await shot("02_wiring.png")

	# передатчик: стрелка у шёпота — в шуме проступает лицо
	var t: RefCounted = open("transmitter")
	t.band = 1
	t.freq = t.decoy + .005
	t.lock = .2
	t.clock = 3.0
	await shot("03_transmitter_whisper.png")
	t.freq = t.target()
	t.lock = 1.0
	await shot("03b_transmitter_clean.png")

	# насос: показ порядка болтов, из трубы смотрят глаза
	var b: RefCounted = open("pump")
	b.show_time = b.STEP * 1.2
	b.eyes = 1.0
	await shot("04_pump_bolts.png")

	# двигатель: метки падают, одна чёрная
	var e: RefCounted = open("ship_engine")
	e.notes[3].black = true
	e.time = float(e.notes[2].t) - .2
	e.rpm = .4
	e.mistakes = 1
	await shot("05_engine_ignition.png")

	# корпус: течи и рука
	var l: RefCounted = open("ship_hull")
	l.holes[0].state = 1
	l.holes[2].state = 1
	l.holes[2].hits = 1
	l.holes[4].state = 2
	l.holes[4].time = .7
	l.water = .35
	l.patched = 2
	l.clock = 1.3
	await shot("06_hull_leaks.png")

	# каменоломня
	var q: RefCounted = open("quarry")
	q.hits = 1
	q.clock = 2.2
	q.aim = q.cracks[1] + Vector2(30, -10) - q.sway()
	await shot("07_quarry.png")
	mini.close()
	quit(0)
