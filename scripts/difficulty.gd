extends RefCounted
## Сложность кампании. «Кошмар»: охотник быстрее (догоняет бегущего), масла меньше и оно горит
## быстрее, сохранений нет — ни у журнала, ни автоматических в начале дня.
const MODES := {
	"normal": {"title": "Обычная", "hunter_speed": 1.0, "oil_drain": 1.0, "oil_start": 1.0, "saves": true,
		"text": "Сохранения у журнала, повтор дня после гибели."},
	"nightmare": {"title": "Кошмар", "hunter_speed": 1.15, "oil_drain": 1.6, "oil_start": .5, "saves": false,
		"text": "Охотник быстрее, масла меньше, сохранений нет. Погибли — начинайте с первого дня."},
}
const ORDER := ["normal", "nightmare"]

static func valid(id: String) -> String:
	return id if MODES.has(id) else "normal"

static func value(id: String, key: String) -> Variant:
	return MODES[valid(id)][key]

static func title(id: String) -> String:
	return str(MODES[valid(id)].title)

static func next(id: String) -> String:
	return ORDER[(ORDER.find(valid(id)) + 1) % ORDER.size()]
