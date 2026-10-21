class_name Events
extends RefCounted
## Minimal publish/subscribe bus. Systems announce what happened; the HUD and
## audio listen. Nothing listening is ever required for gameplay to work.
## Payloads are Dictionaries, as in src/core/events.js.

var _handlers := {}


func on(type: String, fn: Callable) -> void:
	if not _handlers.has(type):
		_handlers[type] = []
	_handlers[type].append(fn)


func off(type: String, fn: Callable) -> void:
	if _handlers.has(type):
		_handlers[type].erase(fn)


func emit(type: String, payload := {}) -> void:
	for fn in _handlers.get(type, []).duplicate():
		if fn.is_valid():
			fn.call(payload)
