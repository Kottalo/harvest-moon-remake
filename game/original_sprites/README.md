# Original NPC, animal and item sprites

`catalogue.json` indexes the USA disc's original ANI ranges by semantic name and
source ID. The NPC pack number selects the original schedule or event art
variant. Wildlife variants use season indices 0–3. Item variants use the source
item art set index or `sector` for the individual disc picture.

`sprite_library.gd` returns a Godot AtlasTexture on the common 256×256 canvas,
with origin (128, 176). Keep that origin fixed across all poses. Duration and
control are the original ANI bytes. A duration is max(1, ceil(duration / 2))
ticks at 30 Hz. A null image marks an empty picture in the original sequence.
The `items_without_picture` index lists named IDs without a picture in the
decoded item banks. Some are actors or field states with their own rendering.

Coverage is limited to the farm resource packs, seasonal wildlife banks,
and item picture banks. Dedicated event-block actors such as Gourmet,
and map models such as the mayonnaise maker, are outside these sprite banks.

These assets are available on demand. Map placement, schedules, dialogue,
livestock gameplay and inventory behavior are separate systems.

Regenerate offline with `python tools/import_original_sprites.py <USA disc>`,
or add `--check` to compare the generated catalogue and atlases to the
checked-in version. Only the packed atlases are imported by Godot.
