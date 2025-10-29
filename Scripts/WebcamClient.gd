# WebcamClient.gd (Godot 4)
extends Node

signal landmarks_received(data: Dictionary)
@export var listen_port: int = 5005

var _udp := UDPServer.new()

func _ready() -> void:
	var ok := _udp.listen(listen_port)
	if ok != OK:
		push_error("UDP listen failed on %d" % listen_port)
		return
	print("UDPClient listening on %d" % listen_port)
	set_process(true)

func _process(_dt: float) -> void:
	if not _udp.is_listening():
		return

	_udp.poll()
	while _udp.is_connection_available():
		var peer: PacketPeerUDP = _udp.take_connection()
		while peer and peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = peer.get_packet()
			var txt: String = pkt.get_string_from_utf8()
			if txt == "":
				continue

			# --- PARSE JSON DENGAN TIPE JELAS ---
			var parsed: Variant = JSON.parse_string(txt)
			if typeof(parsed) == TYPE_DICTIONARY:
				var data: Dictionary = parsed as Dictionary
				emit_signal("landmarks_received", data)
			# (opsional) else: print("Bad JSON:", txt)
