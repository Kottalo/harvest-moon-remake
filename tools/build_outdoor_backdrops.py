"""Bake a nearest-surface continuation field from native scenes; NumPy is offline only."""
import os
os.environ["OPENBLAS_NUM_THREADS"]="1"
os.environ["MKL_NUM_THREADS"]="1"
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
GODOT = ROOT.parent/'Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
GENERATED = ROOT/'tools/generated'
RIGHT = np.array([1, 0, -1])/np.sqrt(2)
UP = np.array([-1, np.sqrt(8), -1])/np.sqrt(10)
BACK = np.cross(RIGHT, UP)
SIZE = 64


def bake(name, source):
    triangles=[];uvs=[];colors=[];slots=[];waters=[]
    for surface in source['surfaces']:
        v=np.asarray(surface['vertices']).reshape(-1,3,3)
        uv=np.asarray(surface['uv']).reshape(-1,3,2)
        col=np.asarray(surface['colors']).reshape(-1,3,3)
        r=np.array(surface['region'])
        uv=r[:2]+uv*r[2:]
        triangles.append(v);uvs.append(uv);colors.append(col)
        slots.extend([surface['slot']]*len(v));waters.extend([surface['water']]*len(v))
    v=np.concatenate(triangles);uv=np.concatenate(uvs);col=np.concatenate(colors)
    projected=np.stack((v@RIGHT,v@UP),axis=-1)
    axes=np.stack((projected[:,1]-projected[:,0],projected[:,2]-projected[:,0]),axis=-1)
    keep=abs(np.linalg.det(axes))>1e-8
    v=v[keep];uv=uv[keep];col=col[keep];projected=projected[keep];axes=axes[keep]
    slots=np.array(slots)[keep];waters=np.array(waters)[keep]
    inv=np.linalg.inv(axes)
    uv_axes=np.stack((uv[:,1]-uv[:,0],uv[:,2]-uv[:,0]),axis=-1)@inv
    low=projected.min(axis=(0,1))-2
    high=projected.max(axis=(0,1))+2
    points=np.stack(np.meshgrid(np.linspace(low[0],high[0],SIZE),np.linspace(low[1],high[1],SIZE)),axis=-1).reshape(-1,2)
    data=np.zeros((len(points),4,4),dtype=np.float32)
    # Triangle-box lower bounds and a centroid upper bound keep the exact
    # nearest-surface result without scanning every triangle's three edges.
    tri_low=projected.min(axis=1);tri_high=projected.max(axis=1)
    centres=projected.mean(axis=1);depths=v@BACK
    for row,p in enumerate(points):
        upper=((centres-p)**2).sum(axis=-1).min()
        gap=np.maximum(np.maximum(tri_low-p,p-tri_high),0)
        selected=np.flatnonzero((gap*gap).sum(axis=-1)<=upper+1e-10)
        tri=projected[selected];rel=p-tri[:,0]
        bary=np.einsum('tij,tj->ti',inv[selected],rel)
        inside=(bary[:,0]>=0)&(bary[:,1]>=0)&(bary.sum(axis=-1)<=1)
        best=np.full(len(selected),np.inf);closest=np.zeros((len(selected),2))
        for a,b in [(0,1),(1,2),(2,0)]:
            edge=tri[:,b]-tri[:,a]
            t=np.clip(((p-tri[:,a])*edge).sum(axis=-1)/np.maximum((edge*edge).sum(axis=-1),1e-20),0,1)
            q=tri[:,a]+t[:,None]*edge
            dist=((p-q)**2).sum(axis=-1)
            use=dist<best;best=np.where(use,dist,best);closest=np.where(use[:,None],q,closest)
        best=np.where(inside,0,best);closest=np.where(inside[:,None],p,closest)
        cb=np.einsum('tij,tj->ti',inv[selected],closest-tri[:,0])
        weights=np.stack((1-cb.sum(axis=-1),cb[:,0],cb[:,1]),axis=-1)
        depth=(weights*depths[selected]).sum(axis=-1)
        chosen=np.where(best<=best.min()+1e-10,depth,-np.inf).argmax()
        index=selected[chosen];weight=weights[chosen]
        out=data[row]
        out[0,:2]=uv[index,0]+uv_axes[index]@(p-projected[index,0])
        out[0,2:]=uv[index].min(axis=0)
        out[1,:]=uv_axes[index].T.reshape(4)
        out[2,:2]=uv[index].max(axis=0);out[2,2]=slots[index];out[2,3]=waters[index]
        out[3,:3]=weight@col[index];out[3,3]=1
    assert np.isfinite(data).all()
    for channel,label in enumerate(['uv','axes','bounds','tint']):
        (GENERATED/f'{name}_edge_{label}.float32').write_bytes(data[:,channel].tobytes())
    return {'name':name,'size':SIZE,'rect':[*low,*(high-low)],'atlases':source['atlases'],'triangles':len(v)}


def run_engine(script):
    result=subprocess.run([str(GODOT),'--headless','--path',str(ROOT),'--script',script],cwd=ROOT,text=True,capture_output=True)
    print(result.stdout, end='')
    assert result.returncode==0 and 'SCRIPT ERROR' not in result.stderr,(result.returncode,result.stderr)


def main():
    run_engine('tools/export_outdoor_backdrops.gd')
    path=GENERATED/'backdrop_geometry.json'
    geometry=json.loads(path.read_text(encoding='utf-8'))
    manifest={'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'maps':[]}
    for name,source in geometry.items():
        assert len(source['atlases'])<=3,(name,source['atlases'])
        manifest['maps'].append(bake(name,source))
        print('BACKDROP_FIELD_OK:',name,flush=True)
    (GENERATED/'backdrop_fields.json').write_text(json.dumps(manifest),encoding='utf-8')
    run_engine('tools/pack_outdoor_backdrops.gd')


def check():
    manifest=json.loads((GENERATED/'backdrop_fields.json').read_text(encoding='utf-8'))
    for info in manifest['maps']:
        fields={label:np.fromfile(GENERATED/f"{info['name']}_edge_{label}.float32",dtype=np.float32).reshape(SIZE,SIZE,4) for label in ['uv','axes','bounds','tint']}
        assert all(np.isfinite(value).all() for value in fields.values())
        lo=fields['uv'][:,:,2:];hi=fields['bounds'][:,:,:2]
        assert (lo<=hi+1e-7).all() and (lo>=-1e-6).all() and (hi<=1+1e-6).all()
        slot=fields['bounds'][:,:,2]
        assert (slot>=-1).all() and (slot<len(info['atlases'])).all()
        assert (fields['tint'][:,:,:3]>=-1e-6).all()
    print('BACKDROP_DATA_OK:',len(manifest['maps']),'fields; finite data, original tile UV bounds, valid existing atlas slots')


if __name__=='__main__':
    import sys
    check() if '--check' in sys.argv else main()
