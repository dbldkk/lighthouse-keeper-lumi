# Источники звука и голоса

Все звуковые файлы проекта либо сделаны с нуля (процедурный синтез), либо собраны из записей
с лицензией **CC0 1.0** (общественное достояние), либо сгенерированы нейросетью с разрешительной
лицензией. Указание авторства для CC0 не требуется, но мы его приводим.

## Голос (assets/audio/voice/*.ogg, assets/audio/first_shift/radio_*.wav)

* Синтез: **Chatterbox Multilingual** (Resemble AI) — модель и код под лицензией **MIT**,
  https://github.com/resemble-ai/chatterbox, офлайн на CPU. В аудио встроен неслышимый водяной знак Perth.
* Тембры голосов — по ~10-секундным образцам чтецов **LibriVox** (общественное достояние, archive.org):
  «Повести Белкина» (`belkintales_1406_librivox`) — Берег-четыре;
  «Авантюристы» (`avanturisty_2201_librivox`) — голос в эфире;
  «Обрыв» (`obryv_1906_librivox`) — капитан на картине;
  «Записки из подполья» (`notes_underground_russian`) — записи прежней смены.
  Образцы: `tools/voice/neural/ref/*.wav`, нарезка — `make_refs.py`.
* Ударения: словарь **Vosk-TTS ru 0.9** (alphacep, Apache 2.0) — только при генерации, в игру не входит.
* Обработка (ffmpeg): полоса рации и компрессия (диспетчер); понижение, обратная реверберация,
  тремоло и помехи (чужой голос); деревянная рубка (капитан); плёнка с плаванием и шипением (записи).
  Скрипты: `tools/voice/neural/`.

## Записи CC0 (freesound.org)

Исходники скачиваются скриптом `tools/audio/fetch_cc0.py` (список — `tools/audio/cc0_sources.json`)
и обрабатываются `tools/audio/horror_sfx.py`: понижение тона, фильтры, реверберация, сжатие.

| Файл кэша | Запись | Автор | Лицензия | Где используется |
|---|---|---|---|---|
| `wind_1.mp3` | [winter wind 01c.aiff by klangfabrik](https://freesound.org/people/klangfabrik/sounds/117513/) | klangfabrik | CC0 1.0 | ambience/wind_loop |
| `wind_2.mp3` | [Winter wind whistling through window.mp3 by audible-edge](https://freesound.org/people/audible-edge/sounds/69512/) | audible-edge | CC0 1.0 | ambience/wind_loop |
| `rain_1.mp3` | [Rain_06.wav by Q.K.](https://freesound.org/people/Q.K./sounds/56311/) | Q.K. | CC0 1.0 | ambience/rain_loop |
| `fire_1.mp3` | [campfire.wav by Spandau](https://freesound.org/people/Spandau/sounds/40699/) | Spandau | CC0 1.0 | ambience/fire_loop |
| `creak_1.mp3` | [Wooden Creak by Mafon2](https://freesound.org/people/Mafon2/sounds/377552/) | Mafon2 | CC0 1.0 | sfx/interact_wood, sfx/creak_1..3 |
| `creak_2.mp3` | [LargeWoodenShip.mp3 by PimFeijen](https://freesound.org/people/PimFeijen/sounds/195193/) | PimFeijen | CC0 1.0 | sfx/interact_wood, sfx/creak_1..3 |
| `creak_3.mp3` | [Squeaky door opened quickly.wav by CastIronCarousel](https://freesound.org/people/CastIronCarousel/sounds/216878/) | CastIronCarousel | CC0 1.0 | sfx/interact_wood, sfx/creak_1..3 |
| `metal_groan_1.mp3` | [Heatpress squeaking and creaking.wav by lolamadeus](https://freesound.org/people/lolamadeus/sounds/161222/) | lolamadeus | CC0 1.0 | ambience/night_drone, sfx/groan_1 (1); sfx/stinger (2) |
| `metal_groan_2.mp3` | [Spring Loaded Metal Door Creak Open Close 02 by leonelmail](https://freesound.org/people/leonelmail/sounds/429130/) | leonelmail | CC0 1.0 | ambience/night_drone, sfx/groan_1 (1); sfx/stinger (2) |
| `foghorn_1.mp3` | [Deep Horn by Vendarro](https://freesound.org/people/Vendarro/sounds/328541/) | Vendarro | CC0 1.0 | sfx/alarm |
| `bell_1.mp3` | [140809_FrybgWb_BellTower_Midnight_F.wav by blaukreuz](https://freesound.org/people/blaukreuz/sounds/240586/) | blaukreuz | CC0 1.0 | sfx/chime (1; 2 — запас) |
| `bell_2.mp3` | [St. Benedict's Abbey bells Atchison KS close 9-28-2019.wav by kb7clx](https://freesound.org/people/kb7clx/sounds/486559/) | kb7clx | CC0 1.0 | sfx/chime (1; 2 — запас) |
| `zap_1.mp3` | [Electric zap.wav by michael_grinnell](https://freesound.org/people/michael_grinnell/sounds/512471/) | michael_grinnell | CC0 1.0 | sfx/zap_1..2 |
| `zap_2.mp3` | [Spark by elliott.klein](https://freesound.org/people/elliott.klein/sounds/189630/) | elliott.klein | CC0 1.0 | sfx/zap_1..2 |
| `hammer_1.mp3` | [hammer v1.wav by blukotek](https://freesound.org/people/blukotek/sounds/337816/) | blukotek | CC0 1.0 | sfx/hammer_1..2 |
| `hammer_2.mp3` | [hammering or knocking sound by deraj](https://freesound.org/people/deraj/sounds/202231/) | deraj | CC0 1.0 | sfx/hammer_1..2 |
| `pick_1.mp3` | [Stone hit by CamoMano](https://freesound.org/people/CamoMano/sounds/431019/) | CamoMano | CC0 1.0 | sfx/pick_1..2 |
| `pick_2.mp3` | [Mining with Pick Axe in a group by MiraclesHappen](https://freesound.org/people/MiraclesHappen/sounds/457585/) | MiraclesHappen | CC0 1.0 | sfx/pick_1..2 |
| `sea_1.mp3` | [Big waves hit land.wav by straget](https://freesound.org/people/straget/sounds/412308/) | straget | CC0 1.0 | ambience/sea_loop (1), music/menu_tide (2) |
| `sea_2.mp3` | [Waves at Baltic Sea shore.wav by pulswelle](https://freesound.org/people/pulswelle/sounds/339517/) | pulswelle | CC0 1.0 | ambience/sea_loop (1), music/menu_tide (2) |
| `knock_1.mp3` | [Knock_the_door.wav by anagar](https://freesound.org/people/anagar/sounds/267931/) | anagar | CC0 1.0 | sfx/knock_1..2, sfx/knock_far |
| `knock_2.mp3` | [Knock on the door by HunteR4708](https://freesound.org/people/HunteR4708/sounds/256513/) | HunteR4708 | CC0 1.0 | sfx/knock_1..2, sfx/knock_far |
| `engine_1.mp3` | [Diesel Truck Idling Front.wav by ibirdfilm](https://freesound.org/people/ibirdfilm/sounds/128160/) | ibirdfilm | CC0 1.0 | ambience/engine_loop |
| `static_1.mp3` | [Static.wav by Jace](https://freesound.org/people/Jace/sounds/17804/) | Jace | CC0 1.0 | sfx/static (1); 2 — запас |
| `static_2.mp3` | [Radio Noise.wav by RutgerMuller](https://freesound.org/people/RutgerMuller/sounds/50750/) | RutgerMuller | CC0 1.0 | sfx/static (1); 2 — запас |
| `splash_1.mp3` | [SPLASH.wav by petenice](https://freesound.org/people/petenice/sounds/9508/) | petenice | CC0 1.0 | sfx/splash_1..2, sfx/interact_fish |
| `splash_2.mp3` | [Water Pour by JohnsonBrandEditing](https://freesound.org/people/JohnsonBrandEditing/sounds/173930/) | JohnsonBrandEditing | CC0 1.0 | sfx/splash_1..2, sfx/interact_fish |
| `pipe_1.mp3` | [Aircon groan by tomwilkinson](https://freesound.org/people/tomwilkinson/sounds/807910/) | tomwilkinson | CC0 1.0 | sfx/groan_2 |
| `sputter_1.mp3` | [R03-12-Antique Auto Sputter and Backfire.wav by craigsmith](https://freesound.org/people/craigsmith/sounds/481663/) | craigsmith | CC0 1.0 | sfx/cough_1..2 |
| `sputter_2.mp3` | [G02-20-Biplane Engine Sputters.wav by craigsmith](https://freesound.org/people/craigsmith/sounds/437744/) | craigsmith | CC0 1.0 | sfx/cough_1..2 |
| `page_1.mp3` | [Paper Flutter .wav by mickdow](https://freesound.org/people/mickdow/sounds/320913/) | mickdow | CC0 1.0 | sfx/interact_paper |
| `sizzle_1.mp3` | [Sizzle / Acid Burn by bottles](https://freesound.org/people/bottles/sounds/382313/) | bottles | CC0 1.0 | sfx/interact_cook |
| `thunder_1.mp3` | [Bass Rumble In The Distance by BrainClaim](https://freesound.org/people/BrainClaim/sounds/273805/) | BrainClaim | CC0 1.0 | ambience/night_drone |

## Синтез (numpy/scipy, без внешних записей)

`tools/audio/horror_sfx.py`: `sfx/interact`, `sfx/interact_metal`, `sfx/clank`, `sfx/tick`, `sfx/thump`,
`sfx/fail`, `sfx/dispel`, `sfx/radio_signal`, `sfx/whisper`, диссонансный гул в `ambience/night_drone`
и `music/menu_tide`, кластер в `sfx/stinger`; запасные варианты для любого файла, если запись CC0 недоступна.
`tools/audio/synth_sfx.py`: шаги `assets/audio/steps/*` (дальше `horror_sfx.py` делает их глуше и
добавляет пространство) и `assets/audio/horror/*`.

Остальная музыка (`music/gramophone.wav`, `music/morning_signal.wav`) — из исходного репозитория, не менялась.
