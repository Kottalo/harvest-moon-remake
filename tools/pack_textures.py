"""Split original ANI sheets offline and build native atlases with Free Texture Packer CLI."""
import argparse
from collections import defaultdict
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT/'tools/texture_packer'
SOURCE = TOOL/'source'
MANIFEST = TOOL/'atlas_manifest.json'
NODE = shutil.which('node')


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data,separators=(',',':')) if path.name=='action_catalog.json' else json.dumps(data,indent=2)
    path.write_text(text+'\n', encoding='utf-8')


def read_manifest_alias(uri):
    return read(MANIFEST)['aliases'].get(uri,uri) if MANIFEST.exists() else uri


def source_path(path):
    """Offline source lookup for existing pixel-verification tools."""
    relative = Path(path).resolve().relative_to(ROOT)
    if Path(path).suffix=='.tres' and MANIFEST.exists():
        uri = 'res://'+relative.as_posix()
        for old,new in read(MANIFEST)['aliases'].items():
            if new==uri: relative = Path(old[6:]); break
    original = ROOT/relative
    stored = SOURCE/relative
    return original if original.exists() and original.suffix=='.png' else stored


def capture():
    # Capture only pre-packing names, never recursively ingest our own output.
    old = read(MANIFEST) if MANIFEST.exists() else {'images': {}}
    generated = {entry['atlas'] for entry in old.get('entries',{}).values()} | set(old.get('obsolete_atlases',[]))
    candidates = {ROOT/p[6:] for p in old['images']}
    candidates.update(p for base in ['game','assets'] for p in (ROOT/base).rglob('*.png')
                      if 'res://'+p.relative_to(ROOT).as_posix() not in generated)
    for path in candidates:
        if path.exists():
            destination = SOURCE/path.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
            sidecar = Path(str(path)+'.import')
            if sidecar.exists(): shutil.copyfile(sidecar, Path(str(destination)+'.import'))
    for name in ['game/player/actions/action_catalog.json', 'game/player/player_animations.json']:
        path = ROOT/name
        # A packed catalogue must never replace the original frame table.
        if not read(path).get('free_texture_packer'):
            write(SOURCE/name, read(path))


def image_hash(image):
    return hashlib.sha256(image.convert('RGBA').tobytes()).hexdigest()


def compact_atlases(entries):
    """Different banks can produce the same complete atlas; share compatible outputs too."""
    owners, aliases = {}, {}
    for uri in sorted({entry['atlas'] for entry in entries.values()}):
        path = ROOT/uri[6:]
        params = Path(str(path)+'.import').read_text(encoding='utf-8').split('[params]',1)[1].strip()
        image = Image.open(path)
        key = (image.size,image_hash(image),params)
        if key in owners: aliases[uri] = owners[key]
        else: owners[key] = uri
    for entry in entries.values(): entry['atlas'] = aliases.get(entry['atlas'],entry['atlas'])
    return aliases


def build():
    assert NODE and (TOOL/'node_modules/free-tex-packer-cli/index.js').exists(), 'Install Node.js and run npm ci in tools/texture_packer first'
    previous = read(MANIFEST) if MANIFEST.exists() else {'entries':{}}
    capture()
    actions = read(SOURCE/'game/player/actions/action_catalog.json')
    normal = read(SOURCE/'game/player/player_animations.json')
    def params_for(uri):
        return (SOURCE/(uri[6:]+'.import')).read_text(encoding='utf-8').split('[params]',1)[1].strip()
    default_params = params_for(actions['banks']['base']['pages'][0])
    action_pages = {p for bank in actions['banks'].values() for p in bank['pages']}
    sheets = {'res://game/player/player_atlas.png', 'res://assets/original/player.png'}
    groups, entries, images, action_keys, normal_keys = defaultdict(list), {}, {}, {}, {}
    frames = TOOL/'frames'
    frames.mkdir(exist_ok=True)
    (frames/'.gdignore').touch()

    def add(key, image, group, output, margin=None):
        image = image.convert('RGBA')
        path = frames/(key+'.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        entries[key] = dict(size=list(image.size), sha256=image_hash(image), group=group,
                            margin=margin or [0,0,0,0])
        groups[group].append(dict(name=key+'.png', path=path.relative_to(ROOT).as_posix()))
        entries[key]['output'] = output

    for path in sorted(SOURCE.rglob('*.png')):
        relative = path.relative_to(SOURCE).as_posix()
        uri = 'res://'+relative
        image = Image.open(path).convert('RGBA')
        images[uri] = dict(size=list(image.size), sha256=image_hash(image))
        if uri in action_pages: continue
        if uri in sheets:
            group = 'normal' if relative.startswith('game/') else 'legacy_player'
            for tile in range(image.width//128*(image.height//128)):
                key = f'player/{group}/tile_{tile:03d}'
                add(key,image.crop((tile%8*128,tile//8*128,tile%8*128+128,tile//8*128+128)),
                    group,'game/player/atlases/'+group)
                if group=='normal': normal_keys[tile] = key
            images[uri]['sheet'] = group
            continue
        if relative.startswith('game/locations/'):
            slug = path.relative_to(SOURCE).parts[2]
            group, output = slug, f'game/locations/{slug}/textures/{slug}_atlas_pack'
        elif relative.startswith('game/player/actions/tool_icons/'):
            group,output = 'tool_icons','game/player/actions/tool_icons/tool_icons_atlas'
        elif relative.startswith('game/items/'):
            group,output = 'items','game/items/textures/items_atlas'
        elif relative.startswith('game/field/'):
            group,output = 'soil','game/field/soil_atlas'
        elif relative.startswith('game/player/'):
            group,output = 'player_misc','game/player/atlases/player_misc'
        else:
            group,output = 'legacy','assets/original/textures/legacy_atlas'
        # Separate import profiles, including raw motion buffers formerly embedded
        # in scenes. Alpha/STP values are never flattened or thresholded.
        profile = Path(str(path)+'.import')
        params = profile.read_text(encoding='utf-8').split('[params]',1)[1].strip() if profile.exists() else ''
        if path.stem.endswith('_motion'):
            params = params.replace('compress/mode=2','compress/mode=0').replace('mipmaps/generate=true','mipmaps/generate=false').replace('process/fix_alpha_border=true','process/fix_alpha_border=false')
        suffix = hashlib.sha256(params.encode()).hexdigest()[:8]
        group += '_'+suffix
        output += '_'+suffix
        key = relative[:-4]
        add(key,image,group,output)
        entries[key]['import_params'] = params
        images[uri]['entry'] = key
    for bank_name, bank in actions['banks'].items():
        pages = {p:Image.open(SOURCE/p[6:]).convert('RGBA') for p in bank['pages']}
        for range_id, poses in bank['ranges'].items():
            for index,pose in enumerate(poses):
                key = f'player/actions/{bank_name}/range_{int(range_id):03d}/frame_{index:03d}'
                x,y,w,h = pose['rect']
                add(key,pages[bank['pages'][pose['page']]].crop((x,y,x+w,y+h)),
                    'actions_'+bank_name,'game/player/actions/atlases/'+bank_name,pose['margin'])
                action_keys[bank_name,int(range_id),index] = key

    projects = TOOL/'projects'
    projects.mkdir(exist_ok=True)
    for group, inputs in sorted(groups.items()):
        output = entries[inputs[0]['name'][:-4]]['output']
        destination = ROOT/Path(output).parent
        destination.mkdir(parents=True, exist_ok=True)
        options = dict(textureName=Path(output).name, width=2048, height=2048,
                       fixedSize=False,powerOfTwo=False,padding=4,extrude=4,
                       allowRotation=False,allowTrim=False,detectIdentical=True,
                       exporter='JsonHash',removeFileExtension=False,prependFolderName=True,
                       textureFormat='png',scale=1,tinify=False,packer='MaxRectsPacker',packerMethod='Smart')
        project = projects/(group+'.ftpp')
        write(project,dict(images=inputs,folders=[],packOptions=options))
        result = subprocess.run([NODE,str(TOOL/'node_modules/free-tex-packer-cli/index.js'),
                                 '--project',str(project),'--output',str(destination)],
                                cwd=ROOT,capture_output=True,text=True)
        assert result.returncode==0 and 'Done' in result.stdout, result.stdout+result.stderr
        outputs = [Path(line[len('Writing '):].strip()) for line in result.stdout.splitlines()
                   if line.startswith('Writing ') and line.endswith('.json')]
        assert outputs, (group,result.stdout)
        found = set()
        for metadata in outputs:
            packed = read(metadata)
            png = metadata.with_suffix('.png')
            atlas = Image.open(png).convert('RGBA')
            atlas_uri = 'res://'+png.relative_to(ROOT).as_posix()
            first = entries[inputs[0]['name'][:-4]]
            params = first.get('import_params',params_for('res://game/player/player_atlas.png') if group=='normal' else default_params)
            # Native motion ImageTextures never ran alpha-border processing.
            if any(item['name'].endswith('_motion.png') for item in inputs):
                params = params.replace('compress/mode=2','compress/mode=0').replace('mipmaps/generate=true','mipmaps/generate=false').replace('process/fix_alpha_border=true','process/fix_alpha_border=false')
            params = params.replace('detect_3d/compress_to=1','detect_3d/compress_to=0')
            cache = f'res://.godot/imported/{png.name}-{hashlib.md5(atlas_uri.encode()).hexdigest()}.ctex'
            sidecar = Path(str(png)+'.import')
            existing = sidecar.read_text(encoding='utf-8') if sidecar.exists() else ''
            if '[params]' not in existing or existing.split('[params]',1)[1].strip()!=params:
                uid = next((line+'\n' for line in existing.splitlines() if line.startswith('uid=')), '')
                sidecar.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'+uid+
                                   f'path="{cache}"\nmetadata={{"vram_texture":false}}\n\n'
                                   f'[deps]\nsource_file="{atlas_uri}"\ndest_files=["{cache}"]\n\n[params]\n'+params+'\n',encoding='utf-8')
            for name,frame in packed['frames'].items():
                key = name[:-4]
                if key not in entries or entries[key]['group']!=group: continue
                assert not frame['rotated'] and not frame['trimmed'], name
                r = frame['frame']; rect = [r['x'],r['y'],r['w'],r['h']]
                image = atlas.crop((r['x'],r['y'],r['x']+r['w'],r['y']+r['h']))
                assert list(image.size)==entries[key]['size'] and image_hash(image)==entries[key]['sha256'], name
                entries[key].update(atlas=atlas_uri,rect=rect,atlas_size=list(atlas.size))
                found.add(key)
        assert found=={item['name'][:-4] for item in inputs}, (group,len(found),len(inputs))
        print('ATLAS_PACK_OK:',group,len(inputs),'source images',flush=True)

    atlas_aliases = compact_atlases(entries)

    def resource(key, target):
        entry = entries[key]
        x,y,w,h = entry['rect']; l,t,ew,eh = entry['margin']
        text = ('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" path="{entry["atlas"]}" id="1"]\n\n'
                '[resource]\natlas = ExtResource("1")\n'
                f'region = Rect2({x}, {y}, {w}, {h})\n'
                f'margin = Rect2({l}, {t}, {ew}, {eh})\nfilter_clip = true\n')
        path = ROOT/target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text,encoding='utf-8')
        return 'res://'+target

    aliases = {}
    for uri,info in images.items():
        if 'entry' in info: aliases[uri] = resource(info['entry'],uri[6:-4]+'.tres')
    for tile,key in normal_keys.items():
        entries[key]['resource'] = resource(key,f'game/player/frames/normal_{tile:03d}.tres')
    for poses in normal['animations']:
        for pose in poses:pose['texture'] = entries[normal_keys[pose['tile']]]['resource']
    normal['free_texture_packer'] = True
    write(ROOT/'game/player/player_animations.json',normal)
    aliases['res://game/player/player_atlas.png'] = entries[normal_keys[0]]['resource']
    for bank_name,bank in actions['banks'].items():
        pages = sorted({entries[key]['atlas'] for lookup,key in action_keys.items() if lookup[0]==bank_name})
        bank['pages'] = pages
        for range_id,poses in bank['ranges'].items():
            for index,pose in enumerate(poses):
                entry = entries[action_keys[bank_name,int(range_id),index]]
                pose.update(page=pages.index(entry['atlas']),rect=entry['rect'])
    actions['free_texture_packer'] = True
    write(ROOT/'game/player/actions/action_catalog.json',actions)
    for base in ['game','assets','scenes','scripts']:
        for path in (ROOT/base).rglob('*'):
            if path.suffix not in ['.json','.gd','.tscn','.tres']: continue
            if path.name in ['player_animations.json','action_catalog.json']: continue
            text = path.read_text(encoding='utf-8'); updated = text
            for old,new in aliases.items():updated = updated.replace(old,new)
            if updated!=text:path.write_text(updated,encoding='utf-8')
    # Tool icon links are outside bank pages and also need canonical resources.
    actions['tool_pictures'] = {k:aliases.get(v,v) for k,v in actions['tool_pictures'].items()}
    write(ROOT/'game/player/actions/action_catalog.json',actions)
    motion = {Path(uri).stem:aliases[uri] for uri in images if uri.endswith('_motion.png')}
    obsolete = sorted(({entry['atlas'] for entry in previous['entries'].values()} | set(atlas_aliases))-{entry['atlas'] for entry in entries.values()})
    write(MANIFEST,dict(images=images,entries=entries,aliases=aliases,motion=motion,obsolete_atlases=obsolete,
                        action_frames=len(action_keys),normal_frames=len(normal_keys)))
    print('ATLAS_BUILD_OK:',len(images),'original PNGs;',len(action_keys),'action frames;',len(normal_keys),'normal tiles')


def check():
    data = read(MANIFEST)
    atlases = {}
    for key,entry in data['entries'].items():
        if entry['atlas'] not in atlases:atlases[entry['atlas']] = Image.open(ROOT/entry['atlas'][6:]).convert('RGBA')
        x,y,w,h = entry['rect']
        assert [w,h]==entry['size'] and image_hash(atlases[entry['atlas']].crop((x,y,x+w,y+h)))==entry['sha256'],key
    for uri,info in data['images'].items():
        image = Image.open(SOURCE/uri[6:])
        assert list(image.size)==info['size'] and image_hash(image)==info['sha256'],uri
    original = read(SOURCE/'game/player/actions/action_catalog.json')
    packed = read(ROOT/'game/player/actions/action_catalog.json')
    for bank_name,bank in original['banks'].items():
        target = packed['banks'][bank_name]
        assert bank['ranges'].keys()==target['ranges'].keys(),bank_name
        for range_id,poses in bank['ranges'].items():
            assert len(poses)==len(target['ranges'][range_id])
            for index,pose in enumerate(poses):
                actual = target['ranges'][range_id][index]
                entry = data['entries'][f'player/actions/{bank_name}/range_{int(range_id):03d}/frame_{index:03d}']
                assert actual==dict(pose,page=target['pages'].index(entry['atlas']),rect=entry['rect']), (bank_name,range_id,index)
    normal = read(ROOT/'game/player/player_animations.json')
    for poses in normal['animations']:
        for pose in poses:
            assert pose['texture']==data['entries'][f'player/normal/tile_{pose["tile"]:03d}']['resource']
    assert (TOOL/'.gdignore').is_file() and (TOOL/'frames/.gdignore').is_file()
    print('ATLAS_PIXELS_OK:',len(data['entries']),'unrotated, unscaled source images/frames;',len(atlases),'runtime atlases; offline frames excluded')


def finish():
    check()
    data = read(MANIFEST)
    retired = list(data['images'])+data.get('obsolete_atlases',[])
    for base in ['game','assets','scenes','scripts']:
        for path in (ROOT/base).rglob('*'):
            if path.suffix not in ['.tscn','.tres','.gd','.json']: continue
            text = path.read_text(encoding='utf-8')
            assert not any(uri in text for uri in retired), f'Original texture still referenced: {path}'
    for uri in data['images']:
        path = ROOT/uri[6:]
        assert path.resolve().is_relative_to(ROOT)
        path.unlink(missing_ok=True)
        Path(str(path)+'.import').unlink(missing_ok=True)
    for uri in data.get('obsolete_atlases',[]):
        for path in [ROOT/uri[6:],ROOT/(uri[6:]+'.import'),(ROOT/uri[6:]).with_suffix('.json')]:
            assert path.resolve().is_relative_to(ROOT)
            path.unlink(missing_ok=True)


def check_imports():
    data = read(MANIFEST)
    atlases = {entry['atlas'] for entry in data['entries'].values()}
    for uri in atlases:
        png = ROOT/uri[6:]
        md5 = ROOT/'.godot/imported'/f'{png.name}-{hashlib.md5(uri.encode()).hexdigest()}.md5'
        assert md5.exists(), f'Await editor texture import: {uri}'
        imported = re.search(r'source_md5="([a-f0-9]+)"',md5.read_text())
        assert imported and imported[1]==hashlib.md5(png.read_bytes()).hexdigest(), f'Stale Godot import: {uri}'
    print('ATLAS_IMPORTS_OK:',len(atlases),'current PNG hashes match the imported cache')


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['build','check','finish','check-imports'])
    args = parser.parse_args()
    {'build':build,'check':check,'finish':finish,'check-imports':check_imports}[args.mode]()
