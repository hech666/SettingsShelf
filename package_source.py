#!/usr/bin/env python3
from pathlib import Path
import hashlib,zipfile,json
root=Path('/var/minis/workspace/SettingsShelf')
out=Path('/var/minis/attachments/SettingsShelf_Source_5.2.0_Names_Icons60.zip')
exclude={'packages','.git','.theos','.theos-ci','.build_stub','__pycache__','objects','native-arm64e'}
def include(p):
 rel=p.relative_to(root)
 if any(part in exclude for part in rel.parts):return False
 if rel.as_posix()=='SOURCE_MANIFEST.sha256':return False
 return p.is_file()
files=sorted(p for p in root.rglob('*') if include(p))
manifest=''.join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n" for p in files)
(root/'SOURCE_MANIFEST.sha256').write_text(manifest)
files.append(root/'SOURCE_MANIFEST.sha256')
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in files:z.write(p,p.relative_to(root))
with zipfile.ZipFile(out) as z:
 assert z.testzip() is None
 for name in z.namelist():z.read(name)
print(json.dumps({'path':str(out),'bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'files':len(files),'crc':'ok'},indent=2))
