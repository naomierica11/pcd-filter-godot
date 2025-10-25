extends Node
## Menerima landmark dari Python lewat UDP dan emit ke controller.

signal landmarks_received(data: Dictionary)

@export var listen_port: int = 5005
@export var listen_addr: String = "0.0.0.0"

var udp := PacketPeerUDP.new()

func _ready() -> void:
	var err: int = udp.bind(listen_port, listen_addr)
	if err != OK:
		push_error("UDP landmark bind failed at %s:%d" % [listen_addr, listen_port])

func _process(_d: float) -> void:
	while udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = udp.get_packet()
		var txt: String = pkt.get_string_from_utf8()
		if txt.is_empty():
			continue

		var any: Variant = JSON.parse_string(txt)
		if typeof(any) != TYPE_DICTIONARY:
			continue

		var data: Dictionary = any as Dictionary
		emit_signal("landmarks_received", data)

func _exit_tree() -> void:
	udp.close()
