class_name Lobby
extends Node
## The first scene. In the browser the game comes in two downloads
## (tools/split_pck.py): index.pck, which the Godot splash waits for, holds
## the scripts, data, UI and character models, enough for the title screen,
## character select and the creator; game.pck holds the world (terrain
## textures, trees, rocks, sounds). The lobby shows the title screen at once
## and fetches game.pck behind it; entering the world waits for the rest of
## the download behind the loading screen, loads the pack and starts the
## game scene, which goes straight in as that character (Game.enter_id).
##
## When the whole game is already here (the editor, a desktop build, a web
## export that was not split) it hands over to the game scene at once and
## the game shows its own title screen, as before.

const GAME_SCENE := "res://game/main.tscn"
const PACK_URL := "game.pck"
const PACK_FILE := "/tmp/game.pck" ## the browser's in-memory file system; gone on reload
## a resource only game.pck has (tools/split_pck.py MARKER)
const GAME_MARKER := "res://assets/environment/nature/trees/Pine_1.gltf"
const RETRY_WAIT := 3.0

# what the title screen reaches through `game` (game.gd has the same names)
var input: GameInput
var pad := Pad.new()
var roster := Roster.new()
var save := SaveManager.new(null)
var hud: LobbyHud
var mouse_aim := true

var title: TitleScreen
var click: AudioStreamPlayer
var loading: LoadingScreen
var status: Label
var http: HTTPRequest
var pack_ready := false
var waiting_id := "" ## the character to play once the pack is in
var retry_in := 0.0
var failures := 0


static func split_build() -> bool:
	return not ResourceLoader.exists(GAME_MARKER)


func _ready() -> void:
	if not split_build():
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	DB.ensure()
	get_window().title = str(DB.text.title.get("name", "Mythkeep"))
	RenderingServer.set_default_clear_color(Color("0d0b09"))
	input = GameInput.new()
	input.name = "Input"
	add_child(input)
	hud = LobbyHud.new()
	add_child(hud)
	title = TitleScreen.new(self)
	hud.root.add_child(title)
	loading = LoadingScreen.new()
	hud.root.add_child(loading)
	status = UI.label(hud.root, "", 12, UI.TEXT_DIM)
	status.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	status.offset_right = -14
	status.offset_bottom = -8
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the same title screen the game shows (game._show_title)
	var r := roster.load_roster(func(k): return save.read(k))
	var note := ""
	if r.get("legacyUnreadable"):
		note = "Your previous save could not be read. It has been kept aside and will not be overwritten."
		save.quarantine(save.read(save.key).get("raw"), save.key)
	for c in roster.list:
		var rs := save.read(c.key)
		if rs.status == "invalid":
			save.quarantine(rs.get("raw"), c.key)
	# every button clicks, as in the game (game._hook_click, audio.click)
	click = AudioStreamPlayer.new()
	click.stream = load(AudioSystem.SFX_DIR + AudioSystem.SFX.click[0])
	click.volume_db = linear_to_db(0.55)
	add_child(click)
	get_tree().node_added.connect(_hook_click)
	_hook_all(title)
	title.open(note, "select" if Game.to_select else "main")
	_fetch()


func _hook_all(n: Node) -> void:
	_hook_click(n)
	for c in n.get_children():
		_hook_all(c)


func _hook_click(n: Node) -> void:
	var b := n as BaseButton
	if b and not b.pressed.is_connected(_play_click):
		b.pressed.connect(_play_click)


func _play_click() -> void:
	if click and click.stream:
		click.play()


## Start (or restart) the download of game.pck.
func _fetch() -> void:
	if http:
		http.queue_free()
	http = HTTPRequest.new()
	http.use_threads = false
	# read up to 4 MB a frame: the default 64 KB caps the download at about
	# 4 MB/s at 60 fps
	http.download_chunk_size = 1 << 22
	# the browser already un-gzips what Pages serves; letting Godot try again
	# fails with RESULT_BODY_DECOMPRESS_FAILED (error 8)
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(_on_fetched)
	var err := http.request(_pack_url())
	if err != OK:
		_failed("could not start (%d)" % err)


## game.pck beside the page, with the build's commit so a new deploy is
## never served from an old cache
func _pack_url() -> String:
	var url := PACK_URL
	if OS.has_feature("web"):
		var page = JavaScriptBridge.eval("window.location.href.split('#')[0].split('?')[0]")
		if page is String:
			url = page.substr(0, page.rfind("/") + 1) + PACK_URL
	if FileAccess.file_exists("res://data/build.json"):
		var b = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
		if b is Dictionary and b.has("commit"):
			url += "?v=" + str(b.commit).uri_encode()
	return url


## The web build's HTTPRequest does not write `download_file`, so the pack
## comes in memory and is written to the browser's in-memory file system here.
func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_failed("error %d / %d" % [result, code])
		return
	var f := FileAccess.open(PACK_FILE, FileAccess.WRITE)
	if f == null or not f.store_buffer(body):
		_failed("could not be stored (%d)" % FileAccess.get_open_error())
		return
	f.close()
	http.queue_free()
	http = null
	if not ProjectSettings.load_resource_pack(PACK_FILE):
		_failed("the download could not be opened")
		return
	pack_ready = true
	failures = 0
	status.text = ""
	if waiting_id != "":
		_go()


func _failed(why: String) -> void:
	push_warning("game.pck: " + why)
	failures += 1
	retry_in = RETRY_WAIT * mini(failures, 5)
	status.text = "The world could not be fetched (%s). Trying again…" % why


func _process(dt: float) -> void:
	pad.poll()
	if pad.active and pad.now.any(func(v): return v):
		hud.set_pad_mode(true)
	if not input.pressed.is_empty() or input.mouse.clicked:
		hud.set_pad_mode(false)
	if hud.modal == "title":
		title.update(dt)
	input.end_frame()
	if retry_in > 0:
		retry_in -= dt
		if retry_in <= 0:
			_fetch()
	if pack_ready or http == null or retry_in > 0:
		return
	var total := http.get_body_size()
	if total <= 0 and OS.has_feature("web"):
		var size = JavaScriptBridge.eval("window.gamePckSize || 0")
		total = int(size) if size != null else 0
	var got := http.get_downloaded_bytes()
	var k := float(got) / total if total > 0 else 0.0
	var line := "Fetching the world… %d%%" % roundi(k * 100) if total > 0 else "Fetching the world… %.0f MB" % (got / 1e6)
	if waiting_id != "":
		loading.show_progress(line, k)
	else:
		status.text = line


## The title screen's Enter World and Create: the game scene plays them
## once the world's pack is in.
func enter_world(id: String) -> void:
	if roster.by_id(id) == null or waiting_id != "":
		return
	waiting_id = id
	roster.touch(id)
	hud.modal = "loading"
	title.close()
	status.text = ""
	loading.open()
	loading.show_progress("Fetching the world…", 0.0)
	if pack_ready:
		_go()


func _go() -> void:
	loading.show_progress("Raising the world…", 1.0)
	Game.enter_id = waiting_id
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
