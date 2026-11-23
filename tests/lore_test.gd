extends SceneTree
## Сюжет: находки на острове, журнал, кассеты, выбор последней ночи и три концовки.
var game: Node
var lore: Node
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

func fresh() -> void:
	game.start_shift()
	await frames(2)

func final_night() -> void:
	var last: int = game.campaign.final_night()
	game.day = last
	game.campaign.state.day = last
	game.campaign.state.night = false
	game.campaign.ensure_day()
	for i in game.campaign.entry().goals.size():
		game.campaign.state.marks[str(i)] = true
	game.campaign.state.night = true
	game.campaign.state.blackout = true
	game.campaign.state.need_radio = true
	game.lighthouse_on = false

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.checkpoints_enabled = false
	game.save_path = "user://automated_lore.json"
	lore = game.lore
	await fresh()
	check(lore.total() >= 10, "At least ten lore records exist (%d)" % lore.total())
	var kinds := {}
	for it in lore.ITEMS:
		kinds[it.kind] = true
		if it.kind == "tape":
			check(game.radio.LINES.has(it.voice), "Tape %s has a voiced radio line" % it.id)
	check(kinds.has("note") and kinds.has("diary") and kinds.has("tape"), "Notes, diary pages and tapes are all present")
	check(lore.props.is_empty(), "Nothing is on the island on day one")
	game.day = 5
	game.campaign.state.day = 5
	await frames(2)
	var avail := 0
	for it in lore.ITEMS:
		if int(it.day) <= 5:
			avail += 1
	check(lore.props.size() == avail, "Records appear by day (%d on day 5)" % lore.props.size())
	var ok_ground := true
	for id in lore.props:
		var at: Vector3 = lore.props[id].global_position
		ok_ground = ok_ground and game.night_raids.ground_at(at) != null
	check(ok_ground, "Every record lies on walkable ground")

	# подобрать
	var first: String = lore.props.keys()[0]
	game.player.global_position = lore.prop_position(first) + Vector3(.4, .3, 0)
	check(lore.near_item() == first and lore.interact(), "E picks up the record underfoot")
	check(first in lore.found and ("l:" + first) in game.journal_entries, "It is added to the journal")
	await frames(1)
	check(not lore.props.has(first), "Picked records disappear from the island")
	var entry: Dictionary = lore.journal_entry("l:" + first)
	check(not entry.is_empty() and entry.text.length() > 60, "Journal shows the full text")
	game.journal_page = game.journal_entries.find("l:" + first)
	game.open_journal()
	game.journal_page = game.journal_entries.find("l:" + first)
	game.refresh_journal()
	check(game.hud.reader_title.text == entry.title, "The journal UI rereads the record")
	game.close_journal()
	lore.collect("tape_1")
	check(game.radio.current == "tape_1", "A tape plays its voice on pickup")
	check(lore.replay("l:tape_1") and not lore.replay("l:roster"), "Space replays tapes only")

	# сохранение
	check(game.save_game(true), "Save with lore")
	var had: int = lore.count()
	lore.reset()
	check(game.load_game() and lore.count() == had and ("l:tape_1" in game.journal_entries), "Load restores records and journal pages")

	# последняя ночь: выбор
	await final_night()
	check(game.campaign.intercept("beacon") == 1 and lore.choice_open(), "Final-night generator opens the choice")
	check(not lore.choice_buttons.truth.visible, "Hidden option is locked without all records")
	lore.choose("light")
	check(not lore.choice_open() and game.lighthouse_on and lore.ending == "light", "Lighting the beacon continues the campaign")

	# тьма
	await fresh()
	await final_night()
	game.campaign.intercept("beacon")
	lore.choose("dark")
	check(game.finished and lore.ending == "dark" and not game.lighthouse_on, "Letting it go dark ends the game")
	await frames(2)
	if game.album.visible:
		game.album.finish_reel() if game.album.has_method("finish_reel") else null
	game.hud.show_menu("win")
	check(game.hud.menu_title.text == lore.ENDINGS.dark.title and lore.card_visible(), "Dark ending has its own screen and epilogue")
	check(lore.card_text.text.contains("Теперь в темноте ходите вы"), "Dark epilogue text")
	lore.card_layer.hide()

	# правда
	await fresh()
	for it in lore.ITEMS:
		lore.collect(it.id)
	check(lore.complete(), "All records collected")
	await final_night()
	game.campaign.intercept("beacon")
	check(lore.choice_buttons.truth.visible, "Third option unlocks with every record")
	lore.choose("truth")
	game.hud.show_menu("win")
	check(game.finished and lore.ending == "truth" and game.hud.menu_title.text == lore.ENDINGS.truth.title, "Burning the log gives the hidden ending")
	lore.card_layer.hide()

	# обычный путь — свет
	await fresh()
	lore.ending = ""
	game.finish_shift(true)
	game.hud.show_menu("win")
	check(lore.ending == "light" and game.hud.ending_stamp.text == lore.ENDINGS.light.stamp, "Sailing away is the light ending")
	print("LORE_CHECKS ", checks, " failures ", failures)
	quit(1 if failures > 0 else 0)
