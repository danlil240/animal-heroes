class_name DiscoveryService
extends Node


signal host_found(info: Dictionary)

const GameConfig = preload("res://core/game_config.gd")
const Protocol = preload("res://network/protocol.gd")
const ADVERTISEMENT_INTERVAL: float = 0.75
const EXPIRY_SECONDS: float = 2.5

var broadcast_address := "255.255.255.255"
var _sender: PacketPeerUDP
var _receiver: PacketPeerUDP
var _advertisement := PackedByteArray()
var _advertise_elapsed := 0.0
var _discovered: Dictionary = {}


func host(session_id: String, host_address: String = "", game_port: int = GameConfig.GAME_PORT) -> Error:
	var address := host_address if not host_address.is_empty() else _local_ipv4_address()
	_advertisement = Protocol.encode_discovery(session_id, "lobby", address, game_port)
	if _advertisement.is_empty():
		return ERR_INVALID_PARAMETER
	_sender = PacketPeerUDP.new()
	var bind_result := _sender.bind(0, "*")
	if bind_result != OK:
		_sender = null
		return bind_result
	_sender.set_broadcast_enabled(true)
	var destination_result := _sender.set_dest_address(broadcast_address, GameConfig.DISCOVERY_PORT)
	if destination_result != OK:
		_sender = null
		return destination_result
	_advertise_elapsed = ADVERTISEMENT_INTERVAL
	return OK


func listen() -> Error:
	if _receiver != null:
		return OK
	_receiver = PacketPeerUDP.new()
	var bind_result := _receiver.bind(GameConfig.DISCOVERY_PORT, "0.0.0.0")
	if bind_result != OK:
		_receiver = null
		return bind_result
	return OK


func stop() -> void:
	if _sender != null:
		_sender.close()
		_sender = null
	if _receiver != null:
		_receiver.close()
		_receiver = null
	_advertisement = PackedByteArray()
	_discovered.clear()


func known_hosts() -> Array[Dictionary]:
	var hosts: Array[Dictionary] = []
	for entry in _discovered.values():
		hosts.append(entry["info"])
	return hosts


func _process(delta: float) -> void:
	_advertise_elapsed += delta
	if _sender != null and _advertise_elapsed >= ADVERTISEMENT_INTERVAL:
		_sender.put_packet(_advertisement)
		_advertise_elapsed = 0.0
	_poll_discoveries()
	_expire_hosts()


func _poll_discoveries() -> void:
	if _receiver == null:
		return
	while _receiver.get_available_packet_count() > 0:
		ingest_packet(_receiver.get_packet())


func ingest_packet(packet: PackedByteArray) -> bool:
	var info := Protocol.decode_discovery(packet)
	if info.is_empty():
		return false
	var is_new := not _discovered.has(info["session_id"])
	_discovered[info["session_id"]] = {"info": info, "seen_at": Time.get_ticks_msec() / 1000.0}
	if is_new:
		host_found.emit(info)
	return true


func _expire_hosts() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for session_id in _discovered.keys():
		if now - _discovered[session_id]["seen_at"] > EXPIRY_SECONDS:
			_discovered.erase(session_id)


func _local_ipv4_address() -> String:
	for address in IP.get_local_addresses():
		if address != "127.0.0.1" and address.contains("."):
			return address
	return "127.0.0.1"
