"""Extract native player shadow and mine dig texture from the user's verified disc."""
import argparse,hashlib,json,re,struct
from pathlib import Path
from PIL import Image
from import_disc import ROOT,Disc,compose_animations,texture_bank,texture_page

def build(disc,check=False):
    frame=compose_animations(disc.asset(0x25000,0x5800),0x13dc,[24])[0][0]
    assert frame.getbbox()==(53,107,77,116)
    shadow=ROOT/'game/player/player_shadow.png'
    if check:
        assert Image.open(shadow).convert('RGBA').tobytes()==frame.tobytes()
    else: frame.save(shadow)
    source=(ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM/field/mine.c').read_text()
    block=re.search(r'mine_cell_textures\[3\] = \{(.*?)\n\};',source,re.S)[1]
    looks=[([int(x) for x in uv.split(',')],int(clut,16)) for uv,clut in re.findall(r'\{\{([^}]+)\},\s*(0x[0-9A-F]+)\}',block)]
    assert looks[1]==([131,31,131,0,159,31,159,0],0x3de4)
    offsets=[int(x,16) for x in re.findall(r'0x[0-9A-Fa-f]+',(ROOT/'reference/hmbtn-decomp/src/overlay/common/farm_section_table.h').read_text().split('= {',1)[1])]
    catalogue={}
    for area,slug in [(234,'spring_mine'),(245,'lake_mine')]:
        texture,end=offsets[area*4+1:area*4+3]
        vram,_=texture_bank(disc.asset(texture,end-texture))
        image=texture_page(vram,9,looks[1][1])
        path=ROOT/f'game/field/{slug}_dug_soil.png'
        if check: assert Image.open(path).convert('RGBA').tobytes()==image.tobytes()
        else: image.save(path)
        surfaces=json.loads((ROOT/f'tools/generated/locations/{slug}.json').read_text())['surfaces']
        floor=[s for s in surfaces if any(f&8 for f in s['primitive_flags'])]
        assert len(floor)==1 and len(floor[0]['primitive_flags'])==200
        floor=floor[0]
        # Source FT4 vertices become 0,1,2,1,3,2; verify the retextured UV map
        # against all 100 actual cells, including reordered boundary quads.
        orientations=[None]*100
        for i in range(0,len(floor['vertices']),18):
            vertices=[floor['vertices'][j:j+3] for j in range(i,i+18,3)]
            xmin,zmin=min(v[0] for v in vertices),min(v[2] for v in vertices)
            local=[(round((p[0]-xmin)/0.4),round((p[2]-zmin)/0.4)) for p in vertices]
            expected=[(looks[1][0][c*2]-131,looks[1][0][c*2+1]) for c in [0,1,2,1,3,2]]
            for code in range(8):
                mapped=[]
                for x,z in local:
                    u,v=(z,x) if code&1 else (x,z)
                    mapped.append((28*(1-u if code&2 else u),31*(1-v if code&4 else v)))
                if mapped==expected: break
            else: raise AssertionError((area,i,'Not a square mine cell'))
            index=round((zmin+2)/0.4)*10+round((xmin+2)/0.4)
            assert orientations[index] is None
            orientations[index]=code
        assert None not in orientations
        catalogue[str(area)]={'bare_texture':f'res://game/locations/{slug}/'+floor['texture'],'dug_texture':f'res://game/field/{slug}_dug_soil.png','orientations':orientations}
    catalogue['source']='mine.c mine_dig/mine_world_to_cell/mine_retexture_cell; 10x10, origin (-2,-2), step .4; clear UV 131..159 x 0..31, CLUT 0x3DE4 page 9'
    target=ROOT/'game/field/mine_field_catalog.json'
    if check: assert json.loads(target.read_text())==catalogue
    else: target.write_text(json.dumps(catalogue,indent=2)+'\n',encoding='utf-8')
    print('SHADOW_MINE_ASSETS_OK: original UI range 24 frame 0; both mine CLUT pages; all 200 source cell quads/UVs; pixels verified' if check else 'SHADOW_MINE_ASSETS_EXPORTED')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('disc',type=Path);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    expected=json.loads((ROOT/'tools/generated/source_manifest.json').read_text())['disc_sha256']
    with args.disc.open('rb') as file: assert hashlib.file_digest(file,'sha256').hexdigest()==expected
    build(Disc(args.disc),args.check)
