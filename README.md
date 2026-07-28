## Готово — веб-билд уменьшен с 762.9 MB → 149.7 MB (−80%)

| Файл | Было | Стало |
|------|-----:|-----:|
| `index.pck` | 744.0 MB | **131.1 MB** |
| `index.wasm` | 18.15 MB | 18.15 MB |
| `index.js` | 437 KB | 437 KB |
| **Итого** | **762.9 MB** | **149.7 MB** |

Цель ≤500 MB — ✅ перевыполнена. Что сделали: извлекли встроенные текстуры из `.tres`/`.material` (−242 MB), сжали крупные текстуры в Lossy (−280 MB), узкий `export_filter` (−50–120 MB), отключили mobile-VRAM (−80 MB). Экспорт чистый, 0 ошибок. Подробный план: [`plans/web-build-optimization.md`](plans/web-build-optimization.md:1).

---

## ⚠️ Что НЕ делать, чтобы размер не вернулся к ~1 GB

1. **НЕ встраивай картинки в `.tres`/`.material`.** Если файл ресурса весит мегабайты — внутри снова лежит `PoolByteArray(...)`. Храни текстуры как **внешние** `.png`/`.jpg` и подключай по пути. После импорта новых мешей/материалов проверяй: `grep PoolByteArray *.tres *.material` — пусто = ок. Если появились — пере-extract'и через [`tools/extract_embedded_textures.gd`](tools/extract_embedded_textures.gd:1).

2. **НЕ импортируй текстуры в Lossless.** В `.import` держи `compress/mode=1` (Lossy, quality 0.7–0.85) для окружения. Normal-map'ы можно в lossless. ❗ **`mode=2` (VRAM/S3TC) крашит Godot 3.6.2 — НЕ используй его.**

3. **НЕ возвращай `export_filter` в `all_resources`.** Держи `"resources"` + явный список сцен в `export_files` ([`export_presets.cfg`](export_presets.cfg:1)). Иначе в пак упадут сырые `.glb/.gltf/.obj/.png` и размер удвоится.

4. **НЕ включай `vram_texture_compression/for_mobile=true`** для веб-пресета — только desktop. Mobile добавляет ~80 MB лишних GPU-форматов.

5. **Следи за разрешениями.** Для веба 2048 — максимум, лучше 1024. Новые меши делай low-poly где можно (ты их и так добавляешь — это второй приоритет после текстур).

6. **Регулярно проверяй размер `index.pck`** после экспорта в [`C:\Users\prikalel\Documents\Godot Projects\BUILD`](../../../BUILD). Стал расти → ищи встроенные текстуры (п.1) и lossless-импорты (п.2).