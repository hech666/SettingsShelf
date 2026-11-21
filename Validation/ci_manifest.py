#!/usr/bin/env python3
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
record={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in files if name and (root/name).is_file()}
report={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_files':record,'package_version':sys.argv[2],'source_count':len(record)}
Path(sys.argv[1]).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Source manifest:',report['source_commit'],len(record),'files')
