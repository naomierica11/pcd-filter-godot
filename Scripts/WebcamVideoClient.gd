extends Node
# Terima frame JPEG (base64) dari Python dan tampilkan di TextureRect

@export var video_rect_path: NodePath = ^"../MainContainer/CameraContainer/WebcamContainer/WebcamFeed"
@onready var video_rect: TextureRect = null

var udp := PacketPeerUDP.new()
const PORT := 5006

func _ready() -> void:
	video_rect = get_node_or_null(video_rect_path) as TextureRect
	var ok := udp.bind(PORT, "0.0.0.0")
	if ok != OK:
		push_error("UDP video bind failed at %d" % PORT)

func _process(_d: float) -> void:
	while udp.get_available_packet_count() > 0:
		var bytes: PackedByteArray = udp.get_packet()
		var txt: String = bytes.get_string_from_utf8()
		if txt.is_empty():
			continue

		var any: Variant = JSON.parse_string(txt)   # <-- tipe eksplisit
		if typeof(any) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = any as Dictionary     # <-- cast aman

		var b64: String = String(data.get("jpg_b64", ""))  # <-- tipe eksplisit
		if b64.length() == 0:
			continue

		var raw: PackedByteArray = Marshalls.base64_to_raw(b64)
		if raw.is_empty():
			continue

		var img := Image.new()
		var err: int = img.load_jpg_from_buffer(raw)
		if err != OK:
			continue

		var tex: ImageTexture = ImageTexture.create_from_image(img)
		if is_instance_valid(video_rect):
			video_rect.texture = tex
