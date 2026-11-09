extends SceneTree
## Character names (Dan, 2026-11-04): one word of letters only, first letter
## capital, no swear words or slurs (data/meta/blocked_names.json).
##   godot --headless --path . --script res://game/tests/name_rules_check.gd

var failed := 0


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		failed += 1


func _process(_dt: float) -> bool:
	check(Roster.tidy_name("aldric") == "Aldric", "first letter is capitalised")
	check(Roster.tidy_name("ALDRIC") == "Aldric", "the rest is lower case")
	check(Roster.tidy_name("Al dric!\"£$%^&*()<>{}[]@:;/?\\|`¬~#,.") == "Aldric", "spaces and symbols are dropped")
	check(Roster.tidy_name("Wren7") == "Wren", "digits are dropped")
	var r := Roster.new()
	check(r.name_problem("Aldric") == "", "a plain name passes")
	check(r.name_problem("A") != "", "one letter is too short")
	check(r.name_problem("Abcdefghijklm") != "", "13 letters is too long")
	check(r.name_problem("") != "", "an empty name is refused")
	for bad in ["Fuck", "Shithead", "Bitches", "Cunt", "Cunts", "Twat", "Fag", "Faggot", "Nigger", "Retard", "Hitler", "Dicks"]:
		check(r.name_problem(bad) != "", "%s is refused" % bad)
	for good in ["Cassandra", "Scunthorpe", "Dickon", "Hitchcock", "Grape", "Hancock", "Assan", "Titus", "Peacock", "Basil"]:
		check(r.name_problem(good) == "", "%s is allowed" % good)
	var text = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/text.json"))
	var names: Dictionary = text.title.names
	for n in names.first:
		check(r.name_problem(n) == "", "random name %s passes" % n)
	print("name rules: %d failed" % failed)
	quit(1 if failed else 0)
	return true
