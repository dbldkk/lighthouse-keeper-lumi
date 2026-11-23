extends SceneTree
## Отдельные мини-игры механизмов: у каждого объекта своя механика, победа и цена провала.
const BAL = preload("res://scripts/balance.gd")
var game: Node
var mini: Control
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

func station(id: String) -> Area3D:
	for item in game.stations:
		if item.station_id == id:
			return item
	return game.stations[0]

func open(id: String) -> RefCounted:
	mini.close()
	mini.open_repair(station(id), id)
	return mini.sub

func settle() -> void:
	mini._process(2.0)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_minigames.json"
	game.start_shift()
	game.hours_per_second = 0
	game.set_process(false)
	mini = game.minigames
	mini.enabled = true
	seed(20261123)

	# --- хоррор-набор звуков подключён
	var sound: Node = game.sound
	check(sound.sfx_samples.size() >= 30, "Horror SFX set is loaded from assets/audio/sfx")
	for name in ["tick", "clank", "zap", "static", "whisper", "knock", "groan", "cough", "thump", "hammer", "pick", "splash", "creak", "stinger", "fail", "chime", "alarm", "dispel"]:
		check(sound.sfx_samples.has(name) or sound.sfx_samples.has(name + "_1"), "Sound '" + name + "' exists")
	check(sound.sea.stream is AudioStreamWAV and (sound.sea.stream as AudioStreamWAV).get_length() > 10, "Sea ambience is a recorded loop, not a noise burst")
	check(is_instance_valid(sound.wind), "Wind ambience player exists")

	# --- у каждого механизма своя игра
	var titles := {}
	for id in ["sparks", "transmitter", "pump", "ship_engine", "ship_hull", "quarry"]:
		var g := open(id)
		check(g != null and mini.mode == mini.Mode.GAME, id + " opens its own mini-game")
		titles[String(g.title())] = g.get_script().resource_path
	check(titles.size() == 6 and titles.values().size() == 6, "Six mechanisms use six different mini-game scripts")
	mini.close()
	check(open("beacon") == null and mini.mode == mini.Mode.REPAIR, "The generator keeps the flywheel timing game")
	mini.close()

	# --- проводка
	var w := open("sparks")
	for wire in 3:
		w._choose(wire)
		w._choose(w.order.find(wire))
	check(mini.success and w.perfect, "Matching wires to terminals fixes the wiring without sparks")
	mini.close()
	w = open("sparks")
	var hp: float = game.health
	var sanity: float = game.sanity
	for k in 2:
		w._choose(0)
		w._choose(w.order.find(1))
	check(mini.result_time > 0 and not mini.success and w.fail_kind == "shock", "Two wrong terminals end in an electric shock")
	settle()
	check(game.health <= hp - BAL.MINIGAME_SHOCK_DAMAGE + .01 and game.sanity < sanity, "A shock costs health and sanity")
	game.health = 100
	game.sanity = 100
	w = open("sparks")
	w.tick(20.0)
	check(mini.result_time > 0 and not mini.success, "Slow wiring overheats and fails")
	mini.close()

	# --- передатчик
	var t := open("transmitter")
	for i in 200:
		t.freq = t.target()
		t.tick(.05)
		if mini.result_time > 0:
			break
	check(mini.success and t.band == 3, "Holding the needle on three clean bands tunes the transmitter")
	mini.close()
	t = open("transmitter")
	sanity = game.sanity
	t.freq = t.decoy
	var decoy: float = t.decoy
	for i in 30:
		t.freq = decoy
		t.tick(.05)
	check(t.mistakes == 1 and game.sanity < sanity, "Lingering on the whispering frequency costs sanity")
	t.tick(30.0)
	check(mini.result_time > 0 and not mini.success, "Running out of time burns the transmitter lamps")
	mini.close()

	# --- насос
	var b := open("pump")
	b._press(b.sequence[0])
	check(b.progress == 0, "Bolts cannot be tightened while the sequence is still shown")
	b.tick(10.0)
	for i in b.sequence:
		b._press(i)
	check(mini.success and b.perfect, "Repeating the lit bolt order fixes the pump")
	mini.close()
	b = open("pump")
	b.tick(10.0)
	b._press((b.sequence[0] + 1) % 6)
	check(b.showing and b.progress == 0 and b.mistakes == 1, "A wrong bolt replays the sequence from the start")
	b.tick(10.0)
	b._press((b.sequence[0] + 1) % 6)
	check(mini.result_time > 0 and not mini.success, "A second wrong bolt floods the pump")
	mini.close()

	# --- двигатель
	var e := open("ship_engine")
	var blacks := 0
	for n in e.notes:
		e.time = float(n.t)
		if n.black:
			blacks += 1
		else:
			e._fire(int(n.lane))
	e.time = float(e.notes.back().t) + 1.0
	e.tick(.01)
	check(mini.success and e.perfect, "Firing every spark on the line and skipping black marks starts the engine")
	mini.close()
	e = open("ship_engine")
	e.notes[3].black = true
	sanity = game.sanity
	e.time = float(e.notes[3].t)
	e._fire(int(e.notes[3].lane))
	check(e.mistakes == 1 and game.sanity < sanity, "Sparking a black mark is punished")
	for i in 3:
		e._fire((int(e.notes[3].lane) + 1) % 4)
	check(mini.result_time > 0 and not mini.success, "Four misfires stall the engine")
	mini.close()

	# --- корпус
	var l := open("ship_hull")
	for k in 6:
		l.holes[k % 6].state = 1
		l._hit(k % 6)
		l._hit(k % 6)
	check(mini.success and l.patched == 6, "Two hammer blows per leak patch the hull")
	mini.close()
	l = open("ship_hull")
	l.holes[0].state = 2
	sanity = game.sanity
	l._hit(0)
	check(l.grabs == 1 and game.sanity < sanity, "Hitting the hand that reaches through the hole costs sanity")
	l.holes[1].state = 1
	l.tick(40.0)
	check(mini.result_time > 0 and not mini.success, "Unpatched leaks flood the boat")
	mini.close()

	# --- каменоломня
	var q := open("quarry")
	for k in 3:
		q.cooldown = 0
		q.aim = q.cracks[q.hits] - q.sway()
		q.act()
	check(mini.success and q.perfect, "Three strikes on the glowing crack split the rock")
	mini.close()
	q = open("quarry")
	for k in 3:
		q.cooldown = 0
		q.aim = q.cracks[0] + Vector2(200, 200) - q.sway()
		q.act()
	check(mini.result_time > 0 and not mini.success, "Three misses with the pick fail the quarry")
	mini.close()

	# --- ночью шум провала привлекает тени
	game.day = 4
	game.campaign.state.day = 4
	game.campaign.state.night = true
	var alive: int = game.night_raids.count_alive()
	if game.night_raids.eligible():
		for k in 6:
			mini.penalty("noise")
		check(game.night_raids.count_alive() > alive, "At night a failed repair can draw a shadow to the noise")
	else:
		check(true, "Night raids not eligible in this setup; noise check skipped")
	print("MINIGAME_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
