class_name GameConfig
extends RefCounted

const BuildInfo = preload("res://core/build_info.gd")
const PROTOCOL_VERSION: int = BuildInfo.APPLICATION_PROTOCOL_VERSION
const CONTENT_VERSION: String = BuildInfo.VERSION_NAME
const TARGET_FPS: int = 30
const MAX_PLAYERS: int = 2
const GAME_PORT: int = 28740
const DISCOVERY_PORT: int = 28741
const UPDATE_DISCOVERY_PORT: int = 28742
