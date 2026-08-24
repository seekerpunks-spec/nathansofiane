extends Node
## Adaptateur wallet. Le mode desktop utilise le compte dev ; un build release
## refuse ce chemin et attend le bridge Mobile Wallet Adapter Seeker.

func is_dev() -> bool:
	return OS.has_feature("editor") or OS.has_feature("debug")

func address() -> String:
	return Net.DEV_ADDRESS if is_dev() else ""

func sign_nonce(_nonce: String) -> Dictionary:
	if is_dev():
		return {"ok": true, "signature": "dev"}
	return {
		"ok": false,
		"error": "Mobile Wallet Adapter requis sur un appareil Seeker.",
	}
