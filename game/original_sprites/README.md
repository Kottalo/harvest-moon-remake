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
The five soil states are in `field_surfaces`, with source corner order and a
packed tile for each season. Winter uses the same tile across all states, as
in the source field renderer.

The event archive contributes Gourmet, alternate costumes and staged props.
The three makers in `models/` are standalone Godot scenes cut from the original
upgraded coop and barn meshes. Their original placements are in `makers.json`.
The only named item-range IDs without a bound picture are action codes
0x153, 0x155 and 0x159. The original animal action loader does not bind a
sprite for those codes, so they are recorded under `nonvisual_action_ids`.
Dialogue portraits are outside this world-sprite catalogue.

These assets are available on demand. Map placement, schedules, dialogue,
livestock gameplay and inventory behavior are separate systems.

Regenerate offline with `python tools/import_original_sprites.py <USA disc>`,
or add `--check` to compare the generated catalogue and atlases to the
checked-in version. Only the packed atlases are imported by Godot.
