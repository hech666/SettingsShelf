#!/usr/bin/env python3
"""Portable post-build verification for the SettingsShelf package (static only)."""
import hashlib,json,os,plistlib,struct,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def u32(b,o):return struct.unpack_from('<I',b,o)[0]
def be32(b,o):return struct.unpack_from('>I',b,o)[0]
def verify_signature(b):
    pos=32;cs=None
    for _ in range(u32(b,16)):
        cmd,size=struct.unpack_from('<II',b,pos)
        if cmd==0x1d:cs=struct.unpack_from('<II',b,pos+8)
        pos+=size
    assert cs,'missing LC_CODE_SIGNATURE'
    blob=b[cs[0]:cs[0]+cs[1]]
    assert be32(blob,0)==0xfade0cc0,'invalid signature SuperBlob'
    results=[]
    for i in range(be32(blob,8)):
        kind,off=struct.unpack_from('>II',blob,12+8*i)
        if be32(blob,off)!=0xfade0c02:continue
        cd=blob[off:off+be32(blob,off+4)]
        version=be32(cd,8);hashoff=be32(cd,16);n=be32(cd,28);limit=be32(cd,32)
        size,typ,platform,shift=struct.unpack_from('4B',cd,36)
        if version>=0x20300 and limit==0xffffffff:limit=struct.unpack_from('>Q',cd,56)[0]
        assert shift<=16 and 0<limit<=cs[0]
        alg={1:'sha1',2:'sha256',3:'sha256'}.get(typ)
        assert alg,'unsupported code-signature hash type'
        page=1<<shift;assert n==(limit+page-1)//page
        for k in range(n):
            actual=hashlib.new(alg,b[k*page:min((k+1)*page,limit)]).digest()[:size]
            assert actual==cd[hashoff+k*size:hashoff+(k+1)*size],f'CodeDirectory slot {k} mismatch'
        results.append({'hash':alg,'code_pages':n,'verified':True})
    assert results,'no CodeDirectory'
    return results

def verify_macho(path):
    b=path.read_bytes();magic=be32(b,0);slices=[]
    if magic==0xcafebabe:
        for i in range(be32(b,4)):
            cpu,sub,off,size,align=struct.unpack_from('>5I',b,8+20*i)
            slices.append(b[off:off+size])
    else:slices=[b]
    archs=[];details=[]
    for s in slices:
        assert u32(s,0)==0xfeedfacf
        cpu,sub=struct.unpack_from('<II',s,4);assert cpu==0x0100000c
        assert sub in (0,0x80000002),f'unexpected subtype {sub:#x}'
        arch='arm64' if sub==0 else 'arm64e';archs.append(arch)
        details.append({'arch':arch,'cpu_subtype':hex(sub),'signature':verify_signature(s)})
    assert sorted(archs)==['arm64','arm64e'],archs
    return details

def main():
    deb=Path(sys.argv[1]);target=Path(sys.argv[2])
    with tempfile.TemporaryDirectory() as temp:
        subprocess.run(['dpkg-deb','-x',str(deb),temp],check=True)
        base=Path(temp);mains=list(base.rglob('HaogeSettingsShelf.dylib'))
        prefs=[p for p in base.rglob('HaogeSettingsShelfPrefs') if p.is_file()]
        assert len(mains)==len(prefs)==1
        version=subprocess.check_output(['dpkg-deb','-f',str(deb),'Version'],text=True).strip()
        expected=os.getenv('EXPECTED_PACKAGE_VERSION');assert not expected or version==expected
        name=subprocess.check_output(['dpkg-deb','-f',str(deb),'Name'],text=True).strip()
        assert name=='越狱插件和应用软件'
        filtr=plistlib.loads(mains[0].with_suffix('.plist').read_bytes())
        assert filtr=={'Filter':{'Bundles':['com.apple.Preferences']}}
        resources=prefs[0].parent;icons={}
        assert b'PSSwitchCell' not in prefs[0].read_bytes(), 'unexpected preference toggle'
        assert b'HaogeSettingsShelfConfig' not in mains[0].read_bytes(), 'legacy enable gate present'
        assert b'always-on grouping runtime loaded' in mains[0].read_bytes(), 'missing always-on runtime'
        assert not (resources/'HaogeSettingsShelfRoot.plist').exists(), 'legacy switch plist included'
        for name in ('HaogeSettingsShelfApps@2x.png','HaogeSettingsShelfTweaks@2x.png'):
            source=ROOT/'HaogeSettingsShelfPrefs/Resources'/name
            payload=(resources/name).read_bytes()
            assert payload==source.read_bytes()
            assert payload[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack_from('>II',payload,16)==(60,60)
            icons[name]={'pixels':[60,60],'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest()}
        report={'package':deb.name,'version':version,'sha256':hashlib.sha256(deb.read_bytes()).hexdigest(),
                'bytes':deb.stat().st_size,'main':verify_macho(mains[0]),'prefs':verify_macho(prefs[0]),
                'icons':icons,'filter':filtr,'device_tested':False}
        target.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
        print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
