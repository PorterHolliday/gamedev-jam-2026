extends Node

const ALLOWED_DOMAINS = [
	"localhost",
	"127.0.0.1",
	"crazygames.com",
	"crazygames.fr",
	"crazygames.cz",
	"crazygames.co.id",
	"itch.io",
	"itch.zone"
]

func _ready() -> void:
	# Only execute browser-level checks inside Web exports
	if OS.has_feature("web"):
		check_sitelock()

func check_sitelock() -> void:
	var host = JavaScriptBridge.eval("window.location.hostname")
	
	# If hostname cannot be read due to strict security configurations, safely assume it is blocked
	if host == null:
		boot_pirate()
		return
		
	var is_valid = false
	for domain in ALLOWED_DOMAINS:
		if host.ends_with(domain):
			is_valid = true
			break
			
	if not is_valid:
		boot_pirate()

func boot_pirate() -> void:
	# Pause the entire Godot engine scene tree to kill performance/gameplay
	await get_tree().create_timer(0.1).timeout
	GameRoot.enter_sitelock_screen()
	get_tree().paused = true
