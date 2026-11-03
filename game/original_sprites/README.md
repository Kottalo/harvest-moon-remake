# Original NPC, animal and item sprites

`catalogue.json` indexes the USA disc's original ANI ranges by semantic name and
source ID. Numeric NPC packs are farm resource packs. Keys of the form
`event_156_04` identify an event and its actor slot order. Slots can represent
different actors in different events, so select the event variant explicitly.
Wildlife variants use season indices 0–3. Item variants use the source item art
set index, `sector` for an individual disc picture, or `field_N` for crop art
selected by the field renderer. `item_actor_links` maps shared actor art.

`sprite_library.gd` returns a Godot AtlasTexture on the common 256×256 canvas,
with origin (128, 176). Keep that origin fixed across all poses. Duration and
control are the original ANI bytes. A duration is max(1, ceil(duration / 2))
ticks at 30 Hz. A null image marks an empty picture in the original sequence.
The `items_without_picture` index lists named IDs without a picture in the
decoded item banks. Some are actors or field states with their own rendering.

The event archive contributes Gourmet, alternate costumes and staged props.
The three makers in `models/` are standalone Godot scenes cut from the original
upgraded coop and barn meshes. Their original placements are in `makers.json`.
The remaining picture gaps include field surface states and source action IDs
whose art has not been identified. The catalogue does not include face portraits.

These assets are available on demand. Map placement, schedules, dialogue,
livestock gameplay and inventory behavior are separate systems.

Regenerate offline with `python tools/import_original_sprites.py <USA disc>`,
or add `--check` to compare the generated catalogue and atlases to the
checked-in version. Only the packed atlases are imported by Godot.
