#!/usr/bin/env python3
from pathlib import Path
import json, plistlib, struct, subprocess, sys
root=Path(__file__).resolve().parents[1]
for p in root.rglob('*.plist'):
    if any(x in p.parts for x in ('.theos','packages')): continue
    plistlib.loads(p.read_bytes())
control=(root/'control').read_text()
assert 'Package: com.haoge.settingsshelf' in control
assert 'com.axs.tweakshub' in control
assert 'Bundles' in plistlib.loads((root/'HaogeSettingsShelf.plist').read_bytes())['Filter']
assert 'com.apple.Preferences' in plistlib.loads((root/'HaogeSettingsShelf.plist').read_bytes())['Filter']['Bundles']
runtime=(root/'Sources/HaogeSettingsShelfRuntime.m').read_text()
category=(root/'HaogeSettingsShelfPrefs/HaogeSettingsShelfCategoryListController.m').read_text()
assert 'HaogeSettingsShelfCategoryListController' in runtime
assert 'haoge_settingsshelf_snapshot' in category and 'dlsym' in category
assert 'AppBundleID' in (root/'Sources/HaogeSettingsShelfGrouping.m').read_text()
assert not (root/'Sources/HaogeSettingsShelfConfig.m').exists()
assert 'PSSwitchCell' not in (root/'HaogeSettingsShelfPrefs/HaogeSettingsShelfRootListController.m').read_text()
assert 'enabled:YES' in runtime
assert '[live setArray:result]' in runtime
assert '[controller setSpecifiers:' not in runtime
assert 'reloadData' not in runtime
assert 'haoge_settingsshelf_isRoot(controller)' in runtime
assert 'removeContiguousSpecifiers:run animated:NO' in runtime
assert 'addSpecifiersFromArray:missingNavigation animated:NO' in runtime
assert 'if ([controller isViewLoaded]) { haoge_settingsshelf_schedule(controller); return rows; }' in runtime
assert '_insertContiguousSpecifiers:atIndex:animated:' in runtime
# Preserve system insertion arguments, then reconcile through PSListController APIs.
assert 'original)(controller, insertSelector, rows, index, animated);' in runtime
assert 'MAX(0, MIN(index' not in runtime
assert 'haoge_settingsshelf_schedule(controller);' in runtime
assert 'PREFERENCES' not in (root/'Makefile').read_text()
assert (root/'.github/workflows/build.yml').is_file()
assert 'Name: 越狱插件和应用软件' in control
assert json.loads((root/'tweak.json').read_text())['display_name']=='越狱插件和应用软件'
hook=runtime
assert '@"越狱插件"' in hook and '@"应用软件"' in hook
assert '@"应用设置"' not in hook
for filename in ('HaogeSettingsShelfApps@2x.png','HaogeSettingsShelfTweaks@2x.png'):
    data=(root/'HaogeSettingsShelfPrefs/Resources'/filename).read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>II',data,16)==(60,60)
    assert filename in hook
subprocess.run(['sh','-n',str(root/'build.sh')],check=True)
print(json.dumps({'plists':'all valid','package':'com.haoge.settingsshelf','filter':['com.apple.Preferences'],'always_on':True,'legacy_switch_ignored':True,'grouping_model':'present','delayed_insertion_hook':'present','live_array_mutation':'present','shell_build_script':'syntax-ok','theos_link_or_package_build':False},indent=2))
