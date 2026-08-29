class_name BuildInfo
extends RefCounted

const VERSION_NAME := "1.0.0-dev.1"
const VERSION_CODE := 1
const APPLICATION_PROTOCOL_VERSION := 1
const SAVE_SCHEMA_VERSION := 1
const SAVE_SCHEMA_COMPATIBLE_MIN := 1
const SAVE_SCHEMA_COMPATIBLE_MAX := 1

static func current() -> Dictionary:
	return {
		"version_name": VERSION_NAME,
		"version_code": VERSION_CODE,
		"application_protocol_version": APPLICATION_PROTOCOL_VERSION,
		"save_schema_version": SAVE_SCHEMA_VERSION,
	}
