# EthnicityDetectionController.gd (AUTO-DETECT VERSION)
extends Control

# Node references - pakai get_node_or_null biar aman
var webcam_feed: TextureRect
var tie_sprite: Sprite2D
var choker_sprite: Sprite2D
var necklace_sprite: Sprite2D
var option_mode: OptionButton
var status_lbl: Label

# Smoothing parameters
var ema_pos := Vector2.ZERO
var ema_angle := 0.0
var ema_scale := 1.0
const ALPHA_POS := 0.35
const ALPHA_ANG := 0.25
const ALPHA_SCA := 0.30

var last_data: Dictionary
var current_choice: String = "Auto"
var data_received: bool = false
var udp_connected: bool = false

# Offset & scale untuk tiap aksesori (TUNING INI BIAR PAS!)
var accessory_offsets := {
	"tie": Vector2(0, 60),      # Turunin dikit biar di leher
	"choker": Vector2(0, 20),   # Lebih tinggi
	"necklace": Vector2(0, 40)  # Di tengah
}
var accessory_scales := {
	"tie": 1.5,      # Lebih gede biar keliatan
	"choker": 1.0,
	"necklace": 1.6
}

func _ready() -> void:
	print("\n=== CONTROLLER STARTING ===")
	
	# 1. Cari dan connect UDPClient (FLEKSIBEL)
	_connect_udp_client()
	
	# 2. Setup node references
	_setup_node_references()
	
	# 3. Setup UI
	_setup_ui()
	
	# 4. Setup sprites
	_setup_sprites()
	
	print("=== SETUP COMPLETE ===\n")

func _connect_udp_client() -> void:
	var client: Node = null
	
	# Strategi 1: Cari sebagai sibling (sama parent)
	client = get_parent().get_node_or_null("WebcamClient")
	if client == null:
		client = get_parent().get_node_or_null("UDPClient")
	
	# Strategi 2: Cari di root scene
	if client == null:
		var root = get_tree().get_root().get_child(get_tree().get_root().get_child_count() - 1)
		client = root.get_node_or_null("WebcamClient")
		if client == null:
			client = root.get_node_or_null("UDPClient")
	
	# Strategi 3: Cari sebagai child dari node ini
	if client == null:
		client = get_node_or_null("WebcamClient")
		if client == null:
			client = get_node_or_null("UDPClient")
	
	# Strategi 4: Cari rekursif di seluruh tree
	if client == null:
		client = _find_node_by_name(get_tree().root, "WebcamClient")
		if client == null:
			client = _find_node_by_name(get_tree().root, "UDPClient")
	
	# Connect signal
	if client != null:
		if client.has_signal("landmarks_received"):
			client.connect("landmarks_received", Callable(self, "_on_landmarks"))
			udp_connected = true
			print("✓ Connected to: ", client.name, " at path: ", client.get_path())
		else:
			push_error("✗ Node found but signal 'landmarks_received' missing!")
			print("   Available signals: ", client.get_signal_list())
	else:
		push_error("✗ WebcamClient/UDPClient not found in scene tree!")
		print("   Scene structure:")
		_print_tree(get_tree().root, 0)

func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null

func _print_tree(node: Node, indent: int) -> void:
	print("  ".repeat(indent), "- ", node.name, " (", node.get_class(), ")")
	for child in node.get_children():
		_print_tree(child, indent + 1)

func _setup_node_references() -> void:
	# Cari WebcamFeed
	webcam_feed = _find_node_by_type(self, "TextureRect")
	if webcam_feed:
		print("✓ Found WebcamFeed: ", webcam_feed.get_path())
	else:
		push_error("✗ WebcamFeed (TextureRect) not found!")
	
	# Cari sprites
	var sprites = _find_all_nodes_by_type(self, "Sprite2D")
	for sprite in sprites:
		var s = sprite as Sprite2D
		if "Tie" in s.name:
			tie_sprite = s
			print("✓ Found TieSprite: ", s.get_path())
		elif "Choker" in s.name:
			choker_sprite = s
			print("✓ Found ChokerSprite: ", s.get_path())
		elif "Necklace" in s.name or "Kalung" in s.name:
			necklace_sprite = s
			print("✓ Found NecklaceSprite: ", s.get_path())
	
	if not tie_sprite or not choker_sprite or not necklace_sprite:
		push_error("✗ Not all accessory sprites found!")

func _find_node_by_type(root: Node, type: String) -> Node:
	if root.get_class() == type:
		return root
	for child in root.get_children():
		var found = _find_node_by_type(child, type)
		if found:
			return found
	return null

func _find_all_nodes_by_type(root: Node, type: String) -> Array:
	var result: Array = []
	if root.get_class() == type:
		result.append(root)
	for child in root.get_children():
		result.append_array(_find_all_nodes_by_type(child, type))
	return result

func _setup_ui() -> void:
	# Cari OptionButton
	option_mode = _find_node_by_type(self, "OptionButton")
	if option_mode:
		option_mode.clear()
		for m in ["Auto", "Dasi", "Choker", "Kalung"]:
			option_mode.add_item(m)
		option_mode.select(0)
		option_mode.item_selected.connect(Callable(self, "_on_mode_changed"))
		print("✓ OptionButton setup complete")
	
	# Cari Label
	status_lbl = _find_node_by_type(self, "Label")
	if status_lbl:
		status_lbl.text = "Initializing..."
		print("✓ Status label found")

func _setup_sprites() -> void:
	if not tie_sprite or not choker_sprite or not necklace_sprite:
		return
	
	# Setup properties
	for sprite in [tie_sprite, choker_sprite, necklace_sprite]:
		sprite.centered = true
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.z_index = 100
		sprite.z_as_relative = false
	
	# Sembunyikan semua dulu
	_show_only("")
	print("✓ Sprites configured and hidden")
	
	# Status akhir
	if status_lbl:
		if udp_connected:
			status_lbl.text = "Ready! Waiting for camera..."
		else:
			status_lbl.text = "ERROR: UDP not connected!"

func _on_mode_changed(_idx: int) -> void:
	if option_mode:
		current_choice = option_mode.get_item_text(option_mode.get_selected_id())
		print("Mode changed to: ", current_choice)
		_update_accessory()

func _on_landmarks(data: Dictionary) -> void:
	if not data_received:
		print("\n✓✓✓ FIRST UDP PACKET RECEIVED! ✓✓✓")
		print("Data keys: ", data.keys())
		data_received = true
	
	last_data = data
	_apply_accessories(data)

func _to_viewport(norm: Vector2) -> Vector2:
	if not webcam_feed:
		return Vector2.ZERO
	
	var rect: Rect2 = webcam_feed.get_global_rect()
	var tex: Texture2D = webcam_feed.texture
	if tex == null:
		return rect.position
	
	var tex_size: Vector2 = Vector2(tex.get_width(), tex.get_height())
	var rect_size: Vector2 = rect.size
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return rect.position
	
	var tex_aspect: float = tex_size.x / tex_size.y
	var rect_aspect: float = rect_size.x / rect_size.y
	
	var draw_pos: Vector2 = rect.position
	var draw_size: Vector2 = rect_size
	
	if rect_aspect > tex_aspect:
		var new_w: float = rect_size.y * tex_aspect
		var pad_x: float = (rect_size.x - new_w) * 0.5
		draw_pos.x += pad_x
		draw_size.x = new_w
	else:
		var new_h: float = rect_size.x / tex_aspect
		var pad_y: float = (rect_size.y - new_h) * 0.5
		draw_pos.y += pad_y
		draw_size.y = new_h
	
	return Vector2(
		draw_pos.x + norm.x * draw_size.x,
		draw_pos.y + norm.y * draw_size.y
	)

func _apply_accessories(p: Dictionary) -> void:
	if not tie_sprite or not choker_sprite or not necklace_sprite:
		return
	
	# Validasi data
	if not (p.has("neck_anchor") and p.has("angle") and p.has("scale")):
		if status_lbl and data_received:
			status_lbl.text = "Waiting for face detection..."
		return
	
	if p["neck_anchor"] == null:
		return
	
	# Parse data
	var arr: Array = p.get("neck_anchor", [])
	if arr.size() != 2:
		return
	
	var nx: float = float(arr[0])
	var ny: float = float(arr[1])
	var norm_pos: Vector2 = Vector2(nx, ny)
	var screen_pos: Vector2 = _to_viewport(norm_pos)
	
	var angle: float = float(p.get("angle", 0.0))
	var scale_val: float = float(p.get("scale", 1.0))
	
	if not is_finite(angle) or not is_finite(scale_val):
		return
	
	# Init smoothing
	if ema_pos == Vector2.ZERO:
		ema_pos = screen_pos
		ema_angle = angle
		ema_scale = scale_val
	
	# Smoothing
	ema_pos = ema_pos.lerp(screen_pos, ALPHA_POS)
	ema_angle = lerp(ema_angle, angle, ALPHA_ANG)
	ema_scale = lerp(ema_scale, scale_val, ALPHA_SCA)
	
	# Pilih aksesori
	var wearing_shirt: bool = bool(p.get("wearing_shirt_collar", false))
	var which: String = ""
	
	match current_choice:
		"Auto":
			which = "tie" if wearing_shirt else "choker"
		"Dasi":
			which = "tie"
		"Choker":
			which = "choker"
		"Kalung":
			which = "necklace"
	
	# Apply transform
	match which:
		"tie":
			_show_only("tie")
			tie_sprite.global_position = ema_pos + accessory_offsets["tie"]
			tie_sprite.rotation = ema_angle
			tie_sprite.scale = Vector2.ONE * ema_scale * accessory_scales["tie"]
		"choker":
			_show_only("choker")
			choker_sprite.global_position = ema_pos + accessory_offsets["choker"]
			choker_sprite.rotation = 0.0
			choker_sprite.scale = Vector2.ONE * ema_scale * accessory_scales["choker"]
		"necklace":
			_show_only("necklace")
			necklace_sprite.global_position = ema_pos + accessory_offsets["necklace"]
			necklace_sprite.rotation = 0.0
			necklace_sprite.scale = Vector2.ONE * ema_scale * accessory_scales["necklace"]
	
	# Update status
	if status_lbl:
		status_lbl.text = "Mode: %s | Pos(%.0f,%.0f) Rot:%.1f° | Shirt:%s" % [
			current_choice, ema_pos.x, ema_pos.y, rad_to_deg(ema_angle),
			"YES" if wearing_shirt else "NO"
		]

func _show_only(which: String) -> void:
	if tie_sprite:
		tie_sprite.visible = (which == "tie")
	if choker_sprite:
		choker_sprite.visible = (which == "choker")
	if necklace_sprite:
		necklace_sprite.visible = (which == "necklace")

func _update_accessory() -> void:
	if last_data and last_data.size() > 0:
		_apply_accessories(last_data)
