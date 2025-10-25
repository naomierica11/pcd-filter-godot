extends Control

@onready var accessory_layer := $"MainContainer/AccessoryLayer"

@onready var tie_sprite      : Sprite2D = $"MainContainer/AccessoryLayer/TieSprite"
@onready var choker_sprite   : Sprite2D = $"MainContainer/AccessoryLayer/ChokerSprite"
@onready var necklace_sprite : Sprite2D = $"MainContainer/AccessoryLayer/NecklaceSprite"

@onready var option_mode : OptionButton = $"MainContainer/HUD/OptionButton"
@onready var toggle_auto : CheckBox     = $"MainContainer/HUD/CheckBox"
@onready var status_lbl  : Label        = $"MainContainer/HUD/Label"


var last_data: Dictionary = {}
var current_choice: String = "Auto"  # "Auto" | "Dasi" | "Choker" | "Kalung"

func _ready() -> void:
	# Hubungkan ke WebcamClient
	var client := get_tree().get_first_node_in_group("udp_client")
	if client == null:
		client = load("res://scripts/WebcamClient.gd").new()
		add_child(client)
	client.connect("landmarks_received", Callable(self, "_on_landmarks"))

	# init UI
	option_mode.clear()
	for i in ["Auto", "Dasi", "Choker", "Kalung"]:
		option_mode.add_item(i)
	option_mode.select(0)
	option_mode.connect("item_selected", Callable(self, "_on_mode_changed"))

	_show_only("")  # hide all

func _on_mode_changed(idx:int) -> void:
	current_choice = option_mode.get_item_text(idx)
	status_lbl.text = "Mode: %s" % current_choice

func _on_landmarks(data: Dictionary) -> void:
	last_data = data
	status_lbl.text = "UDP OK | ts=%.2f" % float(data.get("ts", 0.0))
	_update_accessory()

func _update_accessory() -> void:
	if last_data.is_empty():
		return

	var chin         = _to_vec2(last_data.get("chin"))
	var neck_base    = _to_vec2(last_data.get("neck_base"))
	var l_sh         = _to_vec2(last_data.get("left_shoulder"))
	var r_sh         = _to_vec2(last_data.get("right_shoulder"))
	var wearing_shirt: bool = bool(last_data.get("wearing_shirt_collar", false))

	# pastikan semua landmark ada
	if chin == null or neck_base == null or l_sh == null or r_sh == null:
		_show_only("")
		return

	var shoulder_dist: float = (l_sh as Vector2).distance_to(r_sh as Vector2)
	if shoulder_dist <= 1.0:
		_show_only("")
		return

	# Tentukan pilihan aksesoris
	var choice: String = current_choice
	if current_choice == "Auto" and toggle_auto.button_pressed:
		choice = "Dasi" if wearing_shirt else "Choker"  # non-shirt bisa diganti "Kalung"

	# Hitung anchor & skala (tipe eksplisit!)
	var anchor: Vector2 = (neck_base as Vector2)
	var scale_factor: float = clampf(shoulder_dist / 220.0, 0.5, 1.6)

	match choice:
		"Dasi":
			_show_only("tie")
			tie_sprite.position = anchor + Vector2(0, 18)
			tie_sprite.scale    = Vector2(scale_factor, scale_factor)
			tie_sprite.rotation = _angle_between(r_sh as Vector2, l_sh as Vector2)

		"Choker":
			_show_only("choker")
			choker_sprite.position = anchor - Vector2(0, 5)
			choker_sprite.scale    = Vector2(scale_factor, scale_factor)
			choker_sprite.rotation = 0.0

		"Kalung":
			_show_only("necklace")
			necklace_sprite.position = anchor + Vector2(0, 12)
			necklace_sprite.scale    = Vector2(scale_factor, scale_factor)
			necklace_sprite.rotation = 0.0

		_:
			_show_only("")

func _angle_between(a: Vector2, b: Vector2) -> float:
	return (b - a).angle()

# biarkan return type Variant (bisa Vector2 atau null)
func _to_vec2(v) -> Variant:
	if typeof(v) == TYPE_NIL:
		return null
	if typeof(v) == TYPE_ARRAY and v.size() == 2:
		return Vector2(v[0], v[1])
	return null

func _show_only(which: String) -> void:
	tie_sprite.visible      = (which == "tie")
	choker_sprite.visible   = (which == "choker")
	necklace_sprite.visible = (which == "necklace")
