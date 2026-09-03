## Automatically copies the pre-built ByteBrew Web SDK bundle into every
## Web export, right next to index.html, so custom_shell.html can load it
## with a plain <script src="bytebrew.bundle.js"> tag.
##
## The bundle is built once (see README.md in this folder) from the
## official bytebrew-web-sdk npm package + esbuild, and committed here as
## a small (~25KB) self-contained file. That avoids ever needing the
## package's full node_modules (tens of MB) inside the project.
##
## NOTE: this writes the file directly to disk in _export_end(), using the
## real output directory captured from _export_begin(). EditorExportPlugin's
## add_file() looked like the "correct" API for this, but its `path` is a
## *virtual* path into the exported .pck, not a real file next to
## index.html on disk - it's the wrong tool for getting a plain static
## asset alongside a Web export's index.html, which is what a raw
## <script src="..."> tag on the page needs.
@tool
extends EditorExportPlugin

const BUNDLE_RES_PATH := "res://addons/bytebrew_web_export/bytebrew.bundle.js"
const BUNDLE_OUTPUT_NAME := "bytebrew.bundle.js"

var _output_dir: String = ""
var _is_web_export: bool = false

func _get_name() -> String:
	return "ByteBrewWebExport"

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform.get_os_name() == "Web"

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	_is_web_export = features.has("web")
	_output_dir = path.get_base_dir()

func _export_end() -> void:
	if not _is_web_export:
		return
	if _output_dir.is_empty():
		push_warning("ByteBrewWebExport: no output directory captured, skipping.")
		return
	if not FileAccess.file_exists(BUNDLE_RES_PATH):
		push_warning("ByteBrewWebExport: bundle not found at %s - ByteBrew will not be included in this export." % BUNDLE_RES_PATH)
		return

	var bytes := FileAccess.get_file_as_bytes(BUNDLE_RES_PATH)
	var out_path := _output_dir.path_join(BUNDLE_OUTPUT_NAME)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("ByteBrewWebExport: failed to write %s (error %s)" % [out_path, FileAccess.get_open_error()])
		return
	f.store_buffer(bytes)
	f.close()
	print("ByteBrewWebExport: wrote %s (%d bytes)" % [out_path, bytes.size()])
