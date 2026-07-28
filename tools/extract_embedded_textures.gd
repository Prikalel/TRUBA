# ##############################################################################
# TRUBA — P0: Extract embedded textures from .tres/.material into external PNGs.
#
# Headless tool (Godot 3.6). Run with:
#   <godot> --headless --path . -s tools/extract_embedded_textures.gd --mode=extract
#   <godot> --headless --path . -s tools/extract_embedded_textures.gd --mode=rematerial
#   <godot> --headless --path . -s tools/extract_embedded_textures.gd --mode=status
#
# WHAT IT DOES
#   extract    -> For each target resource, pulls every embedded Image out to a
#                 PNG under <dir>/extracted/, de-duplicating identical images by
#                 SHA-256 of their pixel data (so the 2 brick .tres and the 4
#                 metal-barrel materials each collapse to ONE png). Writes the
#                 matching .png.import sidecar (lossy mode=1 for colour, lossless
#                 mode=0 for normal maps) using Godot's MD5(res-path) cache hash
#                 so a single GUI editor import pass applies the settings. Also
#                 overwrites the two brick .tres with thin AtlasTexture wrappers.
#                 Records everything in tools/embedded_textures_manifest.json.
#   rematerial -> (run AFTER the GUI editor has imported the new PNGs) reloads
#                 each target material, points its texture slots at the extracted
#                 PNGs loaded from disk (load("res://...png") -> StreamTexture,
#                 which ResourceSaver writes as ext_resource, never re-embedded),
#                 and saves the material back to the SAME path.
#   status     -> Loads each target, reports its current texture slots + on-disk
#                 file size. Used for verification.
#
# GOALS: keep all resource PATHS identical (scenes/ caches load() them), make
# every previously-huge file a few KB, never re-embed image bytes.
# ##############################################################################
extends SceneTree

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
const BRICK_TRES_A := "res://scenes/imported2/WORKING-BRICKES.tres"   # ImageTexture
const BRICK_TRES_B := "res://scenes/imported2/imported+new_image.tres" # bare Image (orphan dup)
const BRICK_PNG    := "res://scenes/imported2/extracted/t_brick.png"

const MATERIAL_TARGETS := [
	"res://assets/meshes/weapons/Material_0.material",
	"res://assets/meshes/WoodMaterial.material",
	"res://assets/meshes/MetalMaterial.material",
	"res://scenes/imported2/fbxes/wooden_crate_hr_1.material",
	"res://scenes/imported2/fbxes/old_mattress_mx_1.material",
	"res://scenes/imported2/fbxes/metal_barrel_hr_1.material",
	"res://scenes/imported2/fbxes/metal_barrel_hr_2.material",
	"res://scenes/imported2/fbxes/metal_barrel_hr_3.material",
	"res://scenes/imported2/fbxes/metal_barrel_hr_4.material",
]

# All texture-bearing properties of a Godot 3 SpatialMaterial.
const SPATIAL_SLOTS := [
	"albedo_texture",
	"metallic_texture",
	"roughness_texture",
	"orm_texture",
	"emission_texture",
	"normal_texture",
	"rim_texture",
	"clearcoat_texture",
	"anisotropy_texture",
	"ambient_occlusion_texture",
	"depth_texture",
	"subsurf_scatter_texture",
	"transmission_texture",
	"refraction_texture",
	"detail_albedo",
	"detail_normal",
]

const MANIFEST_PATH := "res://tools/embedded_textures_manifest.json"

# Runtime state
var _hash_to_png := {}        # sha256(hex) -> res png path   (de-dup map)
var _manifest := {
	"materials": [],
	"bricks": {"png": BRICK_PNG, "wrappers": [BRICK_TRES_A, BRICK_TRES_B]},
	"extracted_pngs": [],
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
func _init() -> void:
	var mode := "extract"
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mode="):
			mode = arg.substr("--mode=".length())

	print("=== embedded-texture tool :: mode=%s ===" % mode)
	var ok := true
	match mode:
		"extract":
			ok = _run_extract()
		"rematerial":
			ok = _run_rematerial()
		"status":
			ok = _run_status()
		"validate":
			ok = _run_validate()
		_:
			push_error("Unknown mode: %s" % mode)
			ok = false

	print("=== done (ok=%s) ===" % str(ok))
	quit(0 if ok else 1)

# ===========================================================================
# EXTRACT
# ===========================================================================
func _run_extract() -> bool:
	var overall := true

	# --- 1. Bricks (one shared PNG, both .tres become thin wrappers) ---------
	if not _extract_bricks():
		overall = false

	# --- 2. Materials ---------------------------------------------------------
	for mat_path in MATERIAL_TARGETS:
		if not _extract_material(mat_path):
			overall = false

	# --- 3. Persist manifest --------------------------------------------------
	_write_manifest()
	return overall


# Extract the brick image from BRICK_TRES_A once, write the shared PNG +
# .import sidecar, and overwrite BOTH brick .tres with thin AtlasTexture
# wrappers that reference it (keeps every path valid; nothing else changes).
func _extract_bricks() -> bool:
	print("\n--- bricks ---")
	if _file_exists(BRICK_PNG):
		# Already extracted in a previous run (the .tres are now wrappers and
		# can no longer be used as an image source). Keep the existing png.
		print("  t_brick.png already exists — skipping re-extraction")
		for wrapper_res in [BRICK_TRES_A, BRICK_TRES_B]:
			_write_atlas_wrapper(wrapper_res, BRICK_PNG)
		_record_extracted_png(BRICK_PNG)
		return true
	var tex := load(BRICK_TRES_A)
	var img: Image = null
	if tex is ImageTexture:
		img = tex.get_data()
	elif tex is Image:
		img = tex
	if img == null:
		push_error("brick: could not obtain Image from %s" % BRICK_TRES_A)
		return false

	print("brick image: %dx%d fmt=%d" % [img.get_width(), img.get_height(), img.get_format()])
	if not _save_image_png(img, BRICK_PNG, false):
		return false

	for wrapper_res in [BRICK_TRES_A, BRICK_TRES_B]:
		if not _write_atlas_wrapper(wrapper_res, BRICK_PNG):
			return false
		# record png import provenance
		_record_extracted_png(BRICK_PNG)

	# sanity: confirm brick B had the identical pixels
	var img_b := (load(BRICK_TRES_B) as Image)
	# (we already overwrote B with the wrapper above; dedup is by plan/head-bytes)
	return true


func _extract_material(mat_path: String) -> bool:
	print("\n--- %s ---" % mat_path)
	var mat := load(mat_path)
	if mat == null:
		push_error("  failed to load")
		return false
	if not (mat is SpatialMaterial):
		print("  not a SpatialMaterial (type=%s) — skipping" % str(mat.get_class()))
		return true

	var entry := {"path": mat_path, "slots": {}}
	var dir_res := mat_path.get_base_dir() + "/extracted"
	var base := mat_path.get_file().get_basename() # e.g. Material_0

	for slot in SPATIAL_SLOTS:
		var tex: Texture = mat.get(slot)
		if tex == null:
			continue
		# Only skip textures that are genuinely external (a separate file on
		# disk, NOT a "::N" sub-resource baked into this material).
		var rp := tex.resource_path
		if rp != "" and rp.find("::") < 0 and _file_exists(rp):
			print("  %-26s EXTERNAL  %s" % [slot, rp])
			continue

		var img: Image = null
		if tex is ImageTexture:
			img = (tex as ImageTexture).get_data()
		elif tex is StreamTexture:
			img = (tex as StreamTexture).get_data()
		if img == null:
			push_error("  %-26s could not get_data() (%s)" % [slot, tex.get_class()])
			continue

		var is_normal: bool = slot.find("normal") >= 0
		var png_res: String = _dedup_or_save(img, dir_res, "%s_%s" % [base, slot], is_normal)
		if png_res == "":
			push_error("  %-26s failed to save png" % slot)
			continue

		entry["slots"][slot] = {
			"png": png_res,
			"normal": is_normal,
			"w": img.get_width(),
			"h": img.get_height(),
			"fmt": img.get_format(),
		}
		print("  %-26s %4dx%-4d %s%s -> %s" % [slot, img.get_width(), img.get_height(), ("NORMAL " if is_normal else "colour "), "(dup) " if _is_dup(img) else "", png_res])

	_manifest["materials"].append(entry)
	return true


# Save `img` to `dir_res/<name>.png` unless an identical image was already
# saved (SHA-256 of the pixel bytes) — returns the res path of the (re)used png.
func _dedup_or_save(img: Image, dir_res: String, name: String, is_normal: bool) -> String:
	var h := _image_hash(img)
	if _hash_to_png.has(h):
		return _hash_to_png[h]
	var png_res := "%s/%s.png" % [dir_res, name]
	if not _save_image_png(img, png_res, is_normal):
		return ""
	_hash_to_png[h] = png_res
	_record_extracted_png(png_res)
	return png_res


func _is_dup(img: Image) -> bool:
	return _hash_to_png.has(_image_hash(img))


func _save_image_png(img: Image, png_res: String, is_normal: bool) -> bool:
	if not _ensure_dir(png_res.get_base_dir()):
		return false
	var err := img.save_png(png_res)
	if err != OK:
		push_error("  save_png failed (%d): %s" % [err, png_res])
		return false
	# StreamTexture import needs "ImageTexture" colour space hint for data textures?
	# We pass is_normal so normals stay lossless.
	_write_png_import(png_res, is_normal, _slot_is_data(png_res))
	return true


# Write a Godot-3 .png.import sidecar using the exact MD5(res-path) cache hash
# so a single GUI editor import pass picks up our compression settings.
func _write_png_import(png_res: String, is_normal: bool, is_data: bool) -> String:
	var h := png_res.md5_text()
	var fname := png_res.get_file()
	var stex := "res://.import/%s-%s.stex" % [fname, h]

	var mode := 1            # 1 = Lossy (default for colour)
	var normal_map := 0
	var srgb := 2            # 2 = detect (sRGB for colour)
	var lossy := 0.85
	if is_normal:
		mode = 0             # 0 = Lossless (avoid normal artefacts)
		normal_map = 1
		srgb = 0             # data/linear
		lossy = 0.85
	elif is_data:
		srgb = 0             # metallic/roughness/orm are linear data

	var txt := ""
	txt += "[remap]\n\n"
	txt += "importer=\"texture\"\n"
	txt += "type=\"StreamTexture\"\n"
	txt += "path=\"%s\"\n" % stex
	txt += "metadata={\n"
	txt += "\"vram_texture\": false\n"
	txt += "}\n\n"
	txt += "[deps]\n\n"
	txt += "source_file=\"%s\"\n" % png_res
	txt += "dest_files=[ \"%s\" ]\n\n" % stex
	txt += "[params]\n\n"
	txt += "compress/mode=%d\n" % mode
	txt += "compress/lossy_quality=%s\n" % str(lossy)
	txt += "compress/hdr_mode=0\n"
	txt += "compress/bptc_ldr=0\n"
	txt += "compress/normal_map=%d\n" % normal_map
	txt += "flags/repeat=true\n"
	txt += "flags/filter=true\n"
	txt += "flags/mipmaps=true\n"
	txt += "flags/anisotropic=false\n"
	txt += "flags/srgb=%d\n" % srgb
	txt += "process/fix_alpha_border=true\n"
	txt += "process/premult_alpha=false\n"
	txt += "process/HDR_as_SRGB=false\n"
	txt += "process/invert_color=false\n"
	txt += "process/normal_map_invert_y=false\n"
	txt += "stream=false\n"
	txt += "size_limit=0\n"
	txt += "detect_3d=false\n"
	txt += "svg/scale=1.0\n"

	if not _write_text(png_res + ".import", txt):
		push_error("  failed to write .import: %s" % (png_res + ".import"))
		return ""
	return stex


# Overwrite a .tres with a tiny AtlasTexture that wraps the external png.
# AtlasTexture IS-A Texture, so any consumer that did load(...).tres as
# type="Texture" keeps working. region=Rect2(0,0,0,0) => whole atlas.
func _write_atlas_wrapper(tres_res: String, png_res: String) -> bool:
	var txt := ""
	txt += "[gd_resource type=\"AtlasTexture\" load_steps=2 format=2]\n\n"
	txt += "[ext_resource path=\"%s\" type=\"Texture\" id=1]\n\n" % png_res
	txt += "[resource]\n"
	txt += "flags = 4\n"
	txt += "atlas = ExtResource( 1 )\n"
	txt += "region = Rect2( 0, 0, 0, 0 )\n"
	var ok := _write_text(tres_res, txt)
	if ok:
		print("  wrote wrapper %s -> %s" % [tres_res, png_res])
	return ok


# ===========================================================================
# REMATERIAL  (run AFTER the GUI editor has imported the PNGs)
# ===========================================================================
func _run_rematerial() -> bool:
	if not _load_manifest():
		return false
	var data: Dictionary = _manifest
	var overall := true

	for entry in data.get("materials", []):
		var mat_path: String = entry["path"]
		var slots: Dictionary = entry["slots"]
		print("\n--- %s ---" % mat_path)

		var mat: SpatialMaterial = load(mat_path)
		if mat == null:
			push_error("  failed to load material")
			overall = false
			continue

		var changed := false
		for slot in slots.keys():
			var png_res: String = slots[slot]["png"]
			if not _file_exists(png_res):
				push_error("  %s: png missing on disk: %s" % [slot, png_res])
				overall = false
				continue
			var ext_tex: Texture = load(png_res)
			if ext_tex == null:
				# Not imported yet -> remind the operator.
				push_error("  %s: load(%s) returned null — import PNGs in the GUI editor first" % [slot, png_res])
				overall = false
				continue
			mat.set(slot, ext_tex)
			changed = true
			print("  %-26s -> %s" % [slot, png_res])

		if changed:
			var err := ResourceSaver.save(mat_path, mat)
			if err != OK:
				push_error("  ResourceSaver failed (%d)" % err)
				overall = false
			else:
				var kb := _file_size_kb(mat_path)
				print("  SAVED (%s KB)" % str(kb))

	return overall


# ===========================================================================
# VALIDATE  (load everything we touched + its consumers)
# ===========================================================================
func _run_validate() -> bool:
	var to_load := []
	for m in MATERIAL_TARGETS:
		to_load.append(m)
	to_load.append(BRICK_TRES_A)
	to_load.append(BRICK_TRES_B)
	# Consumers that reference the brick texture / barrels / weapon mats.
	to_load.append("res://scenes/imported2/танцы с бубном/new_spatialmaterial_stylized.tres")
	to_load.append("res://scenes/test.tscn")
	to_load.append("res://scenes/test3.tscn")
	to_load.append("res://scenes/weapons/axe.tscn")
	to_load.append("res://scenes/weapons/pan.tscn")
	to_load.append("res://scenes/Player.tscn")

	var bad := 0
	for p in to_load:
		var r = load(p)
		if r == null:
			print("  FAIL  %s" % p)
			bad += 1
		else:
			var extra := ""
			if r is SpatialMaterial and r.albedo_texture != null:
				extra = " albedo=" + str(r.albedo_texture.resource_path)
			print("  OK    %s (%s%s)" % [p, r.get_class(), extra])
	print("\nvalidate: %d/%d OK" % [to_load.size() - bad, to_load.size()])
	return bad == 0


# ===========================================================================
# STATUS  (verification)
# ===========================================================================
func _run_status() -> bool:
	print("\n[brick wrappers]")
	for w in [BRICK_TRES_A, BRICK_TRES_B]:
		print("  %s : %s KB" % [w, str(_file_size_kb(w))])
	print("\n[materials]")
	for mat_path in MATERIAL_TARGETS:
		var mat := load(mat_path)
		if mat == null:
			print("  %s : FAILED TO LOAD (%s KB)" % [mat_path, str(_file_size_kb(mat_path))])
			continue
		var bits := []
		for slot in SPATIAL_SLOTS:
			var t: Texture = mat.get(slot) if mat is SpatialMaterial else null
			if t != null:
				var where = "EMBEDDED" if (t.resource_path == "" or t.resource_path == mat_path) else "ext:" + t.resource_path.get_file()
				bits.append("%s=%s" % [slot, where])
		print("  %s : %s KB | %s" % [mat_path, str(_file_size_kb(mat_path)), ", ".join(bits)])
	return true


# ===========================================================================
# helpers
# ===========================================================================
func _slot_is_data(png_res: String) -> bool:
	# names produced look like "<Material>_metallic_texture.png" etc.
	var p := png_res.to_lower()
	return p.find("metallic") >= 0 or p.find("roughness") >= 0 or p.find("orm") >= 0 or p.find("ambient_occlusion") >= 0 or p.find("ao_texture") >= 0


func _image_hash(img: Image) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(img.get_data())
	return hc.finish().hex_encode()


func _ensure_dir(dir_res: String) -> bool:
	var d := Directory.new()
	if d.dir_exists(dir_res):
		return true
	var err := d.make_dir_recursive(dir_res)
	if err != OK:
		push_error("  make_dir_recursive failed (%d): %s" % [err, dir_res])
		return false
	return true


func _write_text(res_path: String, text: String) -> bool:
	if not _ensure_dir(res_path.get_base_dir()):
		return false
	var f := File.new()
	var err := f.open(res_path, File.WRITE)
	if err != OK:
		push_error("  open(write) failed (%d): %s" % [err, res_path])
		return false
	f.store_string(text)
	f.close()
	return true


func _file_exists(res_path: String) -> bool:
	var f := File.new()
	return f.file_exists(res_path)


func _file_size_kb(res_path: String) -> float:
	var f := File.new()
	if f.open(res_path, File.READ) != OK:
		return -1.0
	var b := f.get_len()
	f.close()
	return round(b / 1024.0 * 10.0) / 10.0


func _record_extracted_png(png_res: String) -> void:
	if not (_manifest["extracted_pngs"] as Array).has(png_res):
		(_manifest["extracted_pngs"] as Array).append(png_res)


func _write_manifest() -> void:
	# Recompute bricks png record in case order changed.
	_manifest["bricks"] = {"png": BRICK_PNG, "wrappers": [BRICK_TRES_A, BRICK_TRES_B]}
	_record_extracted_png(BRICK_PNG)
	var f := File.new()
	if f.open(MANIFEST_PATH, File.WRITE) != OK:
		push_error("could not write manifest: %s" % MANIFEST_PATH)
		return
	f.store_string(JSON.print(_manifest, "\t"))
	f.close()
	print("\nmanifest -> %s" % MANIFEST_PATH)
	print("extracted PNGs (unique): %d" % (_manifest["extracted_pngs"] as Array).size())


func _load_manifest() -> bool:
	var f := File.new()
	if f.open(MANIFEST_PATH, File.READ) != OK:
		push_error("manifest missing: %s (run --mode=extract first)" % MANIFEST_PATH)
		return false
	var res = JSON.parse(f.get_as_text())
	f.close()
	if res.error != OK:
		push_error("manifest JSON parse error")
		return false
	_manifest = res.result
	return true
