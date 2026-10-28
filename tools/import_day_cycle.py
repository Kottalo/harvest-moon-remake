"""Extract original clock pause flags, bed triggers and the bedtime ANI, offline only."""
import argparse
import hashlib
import json
import re
import struct
from import_disc import ROOT, Disc
from import_player_actions import export_bank


def extract(path):
    expected = json.loads((ROOT/'tools/generated/source_manifest.json').read_text())['disc_sha256']
    with path.open('rb') as source:
        assert hashlib.file_digest(source, 'sha256').hexdigest() == expected
    disc = Disc(path)
    source = ROOT/'reference/hmbtn-decomp/src/overlay/11_GF_FARM'
    farm = (source/'farm_data.c').read_text()
    places = [int(x) for x in re.search(r'place_entries\[408\] = \{(.*?)\};',farm,re.S)[1].replace('\n','').split(',') if x.strip()]
    offsets = [int(x,16) for x in re.findall(r'0x[0-9a-fA-F]+',(ROOT/'reference/hmbtn-decomp/src/overlay/common/farm_section_table.h').read_text().split('= {',1)[1])]
    locations = json.loads((ROOT/'game/world/location_catalog.json').read_text(encoding='utf-8'))
    areas = {}
    beds = []
    for area,info in locations.items():
        data = disc.asset(offsets[int(area)*4],0xbdc)
        flags = struct.unpack_from('<H',data,8)[0]
        areas[area] = dict(clock_paused=places[info['location']]==0x1000,
                           tint_enabled=not flags&0x1800 and info['location']!=6,source_flags=flags)
        if info['slug']!='farmhouse':
            continue
        for index in range(50):
            pos=16+index*44
            zone_flags,kind=struct.unpack_from('<2H',data,pos)
            if kind!=2 or zone_flags&0x2008: # 0x4000 is an interact-only zone, not disabled.
                continue
            low=struct.unpack_from('<3h',data,pos+14)
            high=struct.unpack_from('<3h',data,pos+20)
            beds.append(dict(area=int(area),index=index,facing=struct.unpack_from('<h',data,pos+8)[0],
                             min=[low[0]/1000,-high[2]/1000],max=[high[0]/1000,-low[2]/1000]))
    assert beds,'Missing source ZONE_PICK_MENU bedside trigger'
    player=(source/'people/player.c').read_text()
    banks=[int(x) for x in re.search(r'player_anim_banks\[28\] = \{(.*?)\};',player,re.S)[1].replace('\n','').split(',') if x.strip()]
    sleep=disc.asset(0x3cb8800+15*0x3800,0x3800) # PLAYER_MODE_GO_TO_BED 0x4A - 0x3B
    ranges,frames=struct.unpack_from('<2I',sleep,28)
    animation=export_bank(sleep,banks[15],range((frames-ranges)//4),'sleep',ROOT/'game/player/actions')
    action_path=ROOT/'game/player/actions/action_catalog.json'
    actions=json.loads(action_path.read_text())
    actions['banks']['sleep']=animation
    action_path.write_text(json.dumps(actions,separators=(',',':')),encoding='utf-8')
    data=dict(areas=areas,beds=beds,wake_area=80,wake_position=[-0.09,0,-0.541],bed_position=[-1.35,0,0.96],
              minute_seconds=0.5,day_start=360,days_per_season=30,
              tint_rgb=[[20,0,0],[0,0,0],[5,30,40],[80,70,45]],tint_ticks=256,
              source='clock.c, clock_events.c, weather.c, farm_data.c, player.c; source zone headers')
    destination=ROOT/'game/time'
    destination.mkdir(exist_ok=True)
    (destination/'day_cycle_catalog.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print('DAY_CYCLE_ASSETS_OK:',len(areas),'source pause/tint flags; bed zones',beds,'sleep ranges',len(animation['ranges']))


if __name__=='__main__':
    from pathlib import Path
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('disc',type=Path)
    extract(parser.parse_args().disc)
