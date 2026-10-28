"""Export source soil palettes, hoe grids and field geometry checks; no runtime disc reads."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from PIL import Image
from import_disc import ROOT, Disc, texture_bank, texture_page


def source_rules():
    field = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/field/field.c').read_text()
    tables = (ROOT/'reference/hmbtn-decomp/src/main/game/farm_tables.c').read_text()
    player = (ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/people/player.c').read_text()
    looks = re.search(r'cell_looks\[30\] = \{(.*?)\n\};',field,re.S)[1]
    looks = [(list(map(int,re.findall(r'\d+',uv))),int(clut,16)) for uv,clut in re.findall(r'\{\{([^}]+)\},\s*(0x[0-9A-F]+)\}',looks)]
    grids = tables.split('static PictureGrid picture_grids',1)[1].split('\n};',1)[0]
    patterns = {}
    for index,body in re.findall(r'/\*\s*(\d+)\s*\*/\s*\{\{(.*?)\}\},',grids,re.S):
        if not 5<=int(index)<=9:
            continue
        grid = [[int(v) for v in re.findall(r'\d+',row)] for row in re.findall(r'\{([^{}]+)\}',body+'}')]
        assert len(grid)==13 and all(len(row)==13 for row in grid)
        oriented = [list(map(list,zip(*grid))),[list(reversed(row)) for row in grid],list(reversed(list(map(list,zip(*grid))))),grid]
        for facing,rotated in enumerate(oriented):
            points = sorted((value,x-6,y-6) for y,row in enumerate(rotated) for x,value in enumerate(row) if value)
            patterns.setdefault(str(facing),[]).append([[x,y] for _,x,y in points])
    limits = [int(v) for v in re.findall(r'\d+',re.search(r'tool_charge_steps_a\[6\] = \{(.*?)\}',player)[1])][:5]
    assert limits==[1,2,3,4,6]
    for patterns_for_facing in patterns.values():
        assert [len(p) for p in patterns_for_facing]==limits
    uv_offsets = [[(look[0][i]-looks[0][0][i])/256 for i in range(2)] for look in looks[:3]]
    for look,offset in zip(looks[:3],uv_offsets):
        assert all((look[0][i]-looks[0][0][i])/256==offset[i%2] for i in range(8))
    mirror = [int(v,16) for v in re.findall(r'0x[0-9A-Fa-f]+',re.search(r'column_mirror_table\[48\] = \{(.*?)\}',field,re.S)[1])][:45]
    return dict(patterns=patterns,step_limits=limits,uv_offsets=uv_offsets,cluts=[v[1] for v in looks[:3]],column_mirror=mirror)


def extract(disc):
    rules = source_rules()
    table = (ROOT/'reference/hmbtn-decomp/src/overlay/common/farm_section_table.h').read_text()
    offsets = [int(v,16) for v in re.findall(r'0x[0-9A-Fa-f]+',table.split('= {',1)[1])]
    vram,_ = texture_bank(disc.asset(offsets[1],offsets[2]-offsets[1]))
    directory = ROOT/'game/field'
    directory.mkdir(exist_ok=True)
    for name,clut in zip(['bare','tilled','watered'],rules['cluts']):
        image = texture_page(vram,8,clut)
        if name!='bare':
            image.save(directory/f'{name}_soil.png')
    data = json.loads((ROOT/'tools/generated/locations/farm.json').read_text())
    field_surfaces = [s for s in data['surfaces'] if any(f&8 for f in s['primitive_flags'])]
    assert len(field_surfaces)==1
    surface = field_surfaces[0]
    indices = [i for i,f in enumerate(surface['primitive_flags']) if f&8]
    assert len(indices)==2250
    for i,flag in enumerate(surface['primitive_flags']):
        if not flag&8:
            points = [surface['vertices'][i*9+j:i*9+j+3] for j in [0,3,6]]
            # No unrelated face shares the field's XZ rectangle at ground height.
            assert (max(p[0] for p in points)<-4.4 or min(p[0] for p in points)>13.6 or
                    max(p[2] for p in points)<-1.6 or min(p[2] for p in points)>8.4 or
                    max(p[1] for p in points)<-0.001 or min(p[1] for p in points)>0.001)
            continue
        assert all(c==1 for c in surface['colors'][i*9:i*9+9])
        for corner in range(3):
            x,y,z = surface['vertices'][i*9+corner*3:i*9+corner*3+3]
            assert y==0
            u,v = surface['uv'][i*6+corner*2:i*6+corner*2+2]
            assert 96<=u*256-0.5<=127 and 176<=v*256-0.5<=207
    bare_uv = [96,207,96,176,127,207,127,176]
    for a,b in zip(indices[::2],indices[1::2]):
        assert b==a+1
        column = round((min(surface['vertices'][a*9:a*9+9:3])+4.4)/0.4)
        expected = bare_uv if rules['column_mirror'][column] else sum([bare_uv[i:i+2] for i in [6,4,2,0]],[])
        points = surface['vertices'][a*9:a*9+9]+surface['vertices'][b*9+3:b*9+6]
        xs,zs = points[0::3],points[2::3]
        actual = []
        for x,z in zip(xs,zs):
            actual.extend([round(127-31*(z-min(zs))/0.4),round(176+31*(x-min(xs))/0.4)])
        assert actual==expected,(column,actual,expected)
    rules.update(bare_texture='res://game/locations/farm/'+surface['texture'],
                 tilled_texture='res://game/field/tilled_soil.png',watered_texture='res://game/field/watered_soil.png',
                 source='field.c field_request_dispatch/field_cell_retexture; farm_tables.c picture_grids; player.c player_result_step')
    (directory/'farm_field_catalog.json').write_text(json.dumps(rules,separators=(',',':')))
    for name,index in [('tilled',1),('watered',2)]:
        exported = Image.open(directory/f'{name}_soil.png').convert('RGBA')
        assert exported.tobytes()==texture_page(vram,8,rules['cluts'][index]).tobytes()
    print('FARM_FIELD_ASSETS_OK: source page 8 + CLUTs',rules['cluts'],'; hoe lengths',rules['step_limits'],'; 1125 original flat field quads; source UV offsets',rules['uv_offsets'])


def check():
    rules = json.loads((ROOT/'game/field/farm_field_catalog.json').read_text())
    for key,value in source_rules().items():
        assert rules[key]==value,(key,'Source field rules changed')
    assert Image.open(ROOT/rules['tilled_texture'][6:]).size==(256,256)
    print('FARM_FIELD_SOURCE_CHECK_OK: four facings, five source hoe levels, palettes/UVs and sequential result limits')


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('disc',nargs='?',type=Path)
    parser.add_argument('--check',action='store_true')
    args = parser.parse_args()
    if args.disc:
        expected = json.loads((ROOT/'tools/generated/source_manifest.json').read_text())['disc_sha256']
        assert hashlib.file_digest(args.disc.open('rb'),'sha256').hexdigest()==expected
        extract(Disc(args.disc))
    check()
