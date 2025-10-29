extends Node

@export var listen_port: int = 5006
@export var webcam_feed_path: NodePath

var _udp := UDPServer.new()
var _img := Image.new()
var _feed: TextureRect

func _ready() -> void:
	# Ambil WebcamFeed dari NodePath; kalau kosong, coba cari otomatis
	_feed = get_node_or_null(webcam_feed_path)
	if _feed == null:
		_feed = get_tree().get_root().find_child("WebcamFeed", true, false) as TextureRect
	if _feed == null:
		push_error("WebcamFeed not found. Set 'webcam_feed_path' on UDPVideoClient.")
		return

	var ok := _udp.listen(listen_port)
	if ok != OK:
		push_error("UDP listen failed on %d" % listen_port)
		return

	print("UDPVideoClient listening on %d" % listen_port)
	set_process(true)

func _process(_dt: float) -> void:
	if not _udp.is_listening(): return

	_udp.poll()
	while _udp.is_connection_available():
		var peer: PacketPeerUDP = _udp.take_connection()
		while peer and peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = peer.get_packet()
			var txt: String = pkt.get_string_from_utf8()
			if txt == "": continue

			var parsed: Variant = JSON.parse_string(txt)
			if typeof(parsed) != TYPE_DICTIONARY: continue
			var data: Dictionary = parsed as Dictionary
			if not data.has("jpg_b64"): continue

			var raw: PackedByteArray = Marshalls.base64_to_raw(String(data["jpg_b64"]))
			if raw.size() == 0: continue

			if _img.load_jpg_from_buffer(raw) == OK:
				var tex: ImageTexture = ImageTexture.create_from_image(_img)
				_feed.texture = tex
