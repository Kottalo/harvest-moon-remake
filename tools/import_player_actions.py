"""Offline source ANI actions, item pictures, new-game field layout and door links."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path
from PIL import Image
from import_disc import ROOT, Disc, compose_animations


def item_half_extents():
    source = (ROOT/'reference/hmbtn-decomp/src/main/game/farm_tables.c').read_text()
    result = {}
    for item,name in [(58,'STONE'),(62,'BRANCH'),(64,'WEEDS')]:
        row = re.search(r'\[ITEM_'+name+r'\] = \{(.*?)(?=\n    \[)',source,re.S)[1]
        width,depth = re.search(r',\s*(\d+),\s*(\d+)\},\s*$',row).groups()
        result[item] = [int(width)/1000,int(depth)/1000]
    return result


def ground_item_frames(disc):
    source = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/farm_data.c').read_text()
    toc = re.search(r'farm_item_toc_0 = \{35, \{(.*?)\}\};',source,re.S)[1]
    offsets = [int(value) for value in re.findall(r'\d+',toc)]
    load = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/farm_load.c').read_text()
    table = re.search(r'farm_item_file_offsets\[11\] = \{(.*?)\};',load,re.S)[1]
    first,last = [int(value,16) for value in re.findall(r'0x[0-9A-Fa-f]+',table)][:2]
    pack = disc.asset(first,last-first)
    return {item:compose_animations(pack[offsets[slot]:],offsets[-1]-offsets[slot],[0])[0][0]
            for item,slot in [(58,0),(62,4),(64,6)]}


def extract_items(disc):
    items = ROOT/'game/items'
    (items/'textures').mkdir(parents=True,exist_ok=True)
    pictures = {}
    half_extents = item_half_extents()
    ground_frames = ground_item_frames(disc)
    for item,name in [(58,'stone'),(62,'branch'),(64,'weeds')]:
        data = disc.asset(0x3c19000+item*2048,2048)
        frames,_,_ = compose_animations(data,0x100,[0,1])
        frames[0].save(items/'textures'/f'{name}.png')
        ground_frames[item].save(items/'textures'/f'{name}_ground.png')
        pictures[str(item)] = dict(name=name,texture=f'res://game/items/textures/{name}.png',
            ground_texture=f'res://game/items/textures/{name}_ground.png',half_extents=half_extents[item],
            source_flags=0x8000,place_on_farm=item in [58,62],pickup=True,
            tool={58:'hammer',62:'axe',64:'sickle'}[item])
    title = (ROOT/'reference/hmbtn-decomp/src/overlay/27_GF_TITLE/title.c').read_text()
    layout = re.search(r'title_layout0_cells\[1126\] = \{(.*?)\};',title,re.S)[1]
    cells = [int(x,16) for x in re.findall(r'0x[0-9a-fA-F]+',layout)][:1125]
    assert len(cells)==1125
    field = [dict(id=item,cell=i,position=[(i%45*400-4200)/1000,0,(i//45*400-1400)/1000]) for i,item in enumerate(cells) if str(item) in pictures]
    estate = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/estate.c').read_text()
    draw = [int(re.search(r'#define ESTATE_SPRITE_OFFSET_'+axis+r'\s+\(?(-?\d+)',estate)[1]) for axis in 'XYZ']
    (items/'item_catalog.json').write_text(json.dumps(dict(pictures=pictures,initial_farm=field,
        field_cells=cells,ground_draw_offset=[draw[0]/1000,-draw[1]/1000,-draw[2]/1000]),separators=(',',':')),encoding='utf-8')
    return len(field)



def extract_tool_icons(disc):
    # picture_cell_build_prim uses the ordinary per-item ANI, not the tool swing atlas.
    names = [f'{kind}_{grade}' for kind in ['sickle','hoe','axe','hammer','watering_can']
             for grade in ['normal','copper','silver','gold','mystrile']]
    names += ['milker','clippers','brush','bell','animal_medicine','cow_potion','sheep_potion']
    icons = dict(zip(range(1,33),names))
    icons.update({34:'turnip_seeds',56:'fishing_rod',57:'fishing_pole'})
    directory = ROOT/'game/player/actions/tool_icons'
    directory.mkdir(exist_ok=True)
    paths = {}
    for item,name in icons.items():
        frames,_,_ = compose_animations(disc.asset(0x3c19000+item*2048,2048),0x100,[0])
        frames[0].save(directory/f'{name}.png')
        paths[str(item)] = f'res://game/player/actions/tool_icons/{name}.png'
    path = ROOT/'game/player/actions/action_catalog.json'
    catalogue = json.loads(path.read_text(encoding='utf-8'))
    catalogue['tool_pictures'] = paths
    path.write_text(json.dumps(catalogue,separators=(',',':')),encoding='utf-8')
    print('TOOL_ICONS_OK:',len(paths),'source item ANI pictures, original canvases retained')



def check_tool_icons(disc=None):
    catalogue = json.loads((ROOT/'game/player/actions/action_catalog.json').read_text(encoding='utf-8'))
    pictures = catalogue['tool_pictures']
    assert {int(item) for item in pictures} == set(range(1,33)) | {34,56,57}
    for item,path in pictures.items():
        image = Image.open(ROOT/path[6:]).convert('RGBA')
        assert image.size == (128,128) and image.getbbox(),path
        if disc:
            frames,_,_ = compose_animations(disc.asset(0x3c19000+int(item)*2048,2048),0x100,[0])
            assert image.tobytes() == frames[0].tobytes(),path
    print('SOURCE_TOOL_ICONS_CHECK_OK: 35 semantic native pictures; original ANI canvas and pixels')


def check_items(disc=None):
    catalogue = json.loads((ROOT/'game/items/item_catalog.json').read_text())
    extents = item_half_extents()
    original = ground_item_frames(disc) if disc else {}
    report = {}
    for key,picture in catalogue['pictures'].items():
        item = int(key)
        assert picture['half_extents']==extents[item], 'Item footprint differs from farm_tables.c'
        ground = Image.open(ROOT/picture['ground_texture'][6:]).convert('RGBA')
        held = Image.open(ROOT/picture['texture'][6:]).convert('RGBA')
        if disc:
            assert ground.tobytes()==original[item].tobytes(), 'Ground ANI offsets differ from field sprite pack'
        report[picture['name']] = dict(half_extents=extents[item],ground_bounds=ground.getchannel('A').getbbox(),held_bounds=held.getchannel('A').getbbox())
    assert catalogue['ground_draw_offset']==[0.15,0.1,0.15]
    print('SOURCE_ITEM_OFFSETS_OK:',json.dumps(report), 'ground draw offset=',catalogue['ground_draw_offset'])


def export_bank(data, offset, ids, name, directory, palette_rule=None):
    ids = list(ids)
    images, ranges, _ = compose_animations(data, offset, ids, palette_rule,256)
    # Deduplicate repeated source poses; bounded pages stay below GPU texture limits.
    unique, lookup, pages = [], {}, []
    for image in images:
        key = image.tobytes()
        if key not in lookup:
            lookup[key] = len(unique)
            unique.append(image)
    atlas = Image.new('RGBA',(1024,2048))
    packed = []
    x=y=row_height=0
    def save_page():
        filename = f'{name}_{len(pages):02d}.png'
        atlas.save(directory/filename)
        pages.append('res://' + (directory/filename).relative_to(ROOT).as_posix())
    for image in unique:
        bounds = image.getchannel('A').getbbox() or (0,0,1,1)
        assert not any(a in [0,256] for a in bounds) or image.getbbox() is None, 'Action exceeds its common canvas'
        width,height = bounds[2]-bounds[0],bounds[3]-bounds[1]
        if x+width+4>1024:
            x=0; y+=row_height; row_height=0
        if y+height+4>2048:
            save_page()
            atlas=Image.new('RGBA',(1024,2048))
            x=y=row_height=0
        atlas.paste(image.crop(bounds),(x+2,y+2))
        packed.append(dict(page=len(pages),rect=[x+2,y+2,width,height],margin=[bounds[0],bounds[1],256-width,256-height]))
        x+=width+4
        row_height=max(row_height,height+4)
    save_page()
    for obsolete in directory.glob(f'{name}_??.png'):
        if 'res://'+obsolete.relative_to(ROOT).as_posix() not in pages:
            obsolete.unlink()
            obsolete.with_name(obsolete.name+'.import').unlink(missing_ok=True)
    output = {}
    for index, frames in zip(ids,ranges):
        for frame in frames:
            slot = lookup[images[frame['tile']].tobytes()]
            frame.update(packed[slot])
            frame.pop('tile')
        output[str(index)] = frames
    return dict(pages=pages,ranges=output)


def extract(disc):
    destination = ROOT/'game/player/actions'
    destination.mkdir(exist_ok=True)
    banks = {}
    base = disc.asset(0x2a800,0x49000)
    banks['base'] = export_bank(base,0xbe08,range(177),'player_actions',destination)
    for tier in range(5):
        def tint(animation, palette, place):
            charged = (animation-72)%5
            if palette == [223,218,221,219,220][charged]:
                return [223,218,221,219,220][tier]
            if place==0x80:
                return ([99,89,163,90,91] if animation>=152 else [112,89,163,90,91])[tier]
            return palette
        banks[f'tool_{tier}'] = export_bank(base,0xbe08,range(72,172),'tool_'+['normal','copper','silver','gold','mystrile'][tier],destination,tint)
    source = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/people/player.c').read_text()
    offsets = [int(x) for x in re.search(r'player_anim_banks\[28\] = \{(.*?)\};',source,re.S)[1].replace('\n','').split(',') if x.strip()]
    for row,name in [(3,'overcharge'),(18,'milker'),(19,'clippers'),(20,'brush'),(21,'bell'),(22,'medicine'),(23,'refill'),(24,'seeds'),(10,'fishing'),(26,'potion')]:
        data = disc.asset(0x3cb8800+row*0x3800,0x3800)
        ranges,frames = struct.unpack_from('<2I',data,28)
        banks[name] = export_bank(data,offsets[row],range((frames-ranges)//4),name,destination)
    # Source offsets are relative to the common player draw origin, not alpha bounds.
    mark = re.search(r'mark_screen_offsets\[16\]\[2\] = \{(.*?)\};',source,re.S)[1]
    item_offsets = [[int(x),int(y)] for x,y in re.findall(r'\{(-?\d+),\s*(-?\d+)\}',mark)]
    catalogue = dict(cell=256,origin=[128,176],banks=banks,item_offsets=item_offsets,
                     tool_charge_ticks=20,overcharge_ticks=61,
                     source='player.c, anim.c, fishing.c; original ANI durations/control/part offsets')
    (destination/'action_catalog.json').write_text(json.dumps(catalogue,separators=(',',':')),encoding='utf-8')

    extract_tool_icons(disc)
    field_count = extract_items(disc)
    for obsolete in destination.glob('tool_level_[0-4]_??.png'):
        obsolete.unlink()
        obsolete.with_name(obsolete.name+'.import').unlink(missing_ok=True)

    path = ROOT/'game/world/location_catalog.json'
    world = json.loads(path.read_text(encoding='utf-8'))
    table = (ROOT/'reference/hmbtn-decomp/src/overlay/common/farm_section_table.h').read_text()
    sections = [int(x,16) for x in re.findall(r'0x[0-9a-fA-F]+',table.split('= {',1)[1])]
    doors = 0
    for area,info in world.items():
        data = disc.asset(sections[int(area)*4],0xbdc)
        entries = {entry['index'] for entry in json.loads((ROOT/info['source_json'][6:]).read_text())['entries']}
        for exit in info['exits']:
            index = struct.unpack_from('<h',data,16+exit['index']*44+12)[0]
            if exit['event']!=99 and not exit['source_flags']&0x200 and index in entries:
                record = 0xbdc-15*44+index*44
                flags = struct.unpack_from('<I',data,record)[0]
                twin = struct.unpack_from('<h',data,record+8)[0] if flags&0x400 else -1
                exit['door'] = dict(model=index,twin=twin if twin in entries else -1)
                doors += 1
    path.write_text(json.dumps(world,ensure_ascii=False,indent=2),encoding='utf-8')
    report = dict(banks={name:len(bank['ranges']) for name,bank in banks.items()},doors=doors,field_items=field_count,source='original USA disc and decomp tables')
    (ROOT/'verification/source-actions-assets.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('ACTION_ASSETS_OK',report)


def check():
    catalogue = json.loads((ROOT/'game/player/actions/action_catalog.json').read_text())
    pages = {}
    checked = 0
    for bank in catalogue['banks'].values():
        for frames in bank['ranges'].values():
            for frame in frames:
                path = bank['pages'][frame['page']]
                if path not in pages:
                    pages[path] = Image.open(ROOT/path[6:]).convert('RGBA')
                page = pages[path]
                x,y,w,h = frame['rect']; left,top,extra_w,extra_h = frame['margin']
                assert x>=2 and y>=2 and x+w<=page.width-2 and y+h<=page.height-2
                assert w+extra_w==256 and h+extra_h==256
                assert left>=0 and top>=0 and left+w<=256 and top+h<=256
                checked += 1
    old = json.loads((ROOT/'game/player/player_animations.json').read_text())
    atlas = Image.open(ROOT/'game/player/player_atlas.png').convert('RGBA')
    base = catalogue['banks']['base']
    for animation in range(15):
        for original,frame in zip(old['animations'][animation],base['ranges'][str(animation)]):
            x,y,w,h = frame['rect']; left,top,_,_ = frame['margin']
            image = Image.new('RGBA',(256,256))
            image.paste(pages[base['pages'][frame['page']]].crop((x,y,x+w,y+h)),(left,top))
            tile = original['tile']
            previous = atlas.crop((tile%8*128,tile//8*128,tile%8*128+128,tile//8*128+128))
            assert image.crop((64,64,192,192)).tobytes()==previous.tobytes(),'Original gait/pivot changed'
    print(f'ACTION_ASSETS_CHECK_OK: {checked} frames; common canvas margins, bounded pages and original 90 frames unchanged')


if __name__=='__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('disc',type=Path,nargs='?')
    parser.add_argument('--check',action='store_true')
    parser.add_argument('--tool-icons-only',action='store_true')
    parser.add_argument('--items-only',action='store_true',help='Refresh ground ANI and source item footprints without rebaking player actions or maps')
    args = parser.parse_args()
    if args.disc:
        expected = json.loads((ROOT/'tools/generated/source_manifest.json').read_text())['disc_sha256']
        assert hashlib.file_digest(args.disc.open('rb'),'sha256').hexdigest()==expected,'Wrong source disc'
        disc = Disc(args.disc)
        if args.tool_icons_only:
            extract_tool_icons(disc)
        elif args.items_only:
            extract_items(disc)
        else:
            extract(disc)
        check_tool_icons(disc)
        check_items(disc)
    else:
        check_tool_icons()
        check_items()
    check()
