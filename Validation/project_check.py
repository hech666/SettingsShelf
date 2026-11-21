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
prefs='\n'.join(p.read_text() for p in (root/'HaogeSettingsShelfPrefs').glob('*.m'))
for label in ('屏蔽部件与维修记录','屏蔽系统更新提示','自定义名称与图标'):
    assert label in prefs, label
for key in ('suppressBatteryServiceWarnings','suppressSoftwareUpdatePrompt'):
    assert key in prefs, key
assert '@"enabled"' not in prefs
assert 'haoge_settingsshelf_guardRootRows' in runtime
assert 'haoge_settingsshelf_applyCustomization' in runtime
assert 'enabled:YES' in runtime
assert '[live setArray:result]' in runtime
assert '[controller setSpecifiers:' not in runtime
assert 'reloadData' not in runtime
assert 'haoge_settingsshelf_isRoot(controller)' in runtime
assert 'removeContiguousSpecifiers:run animated:NO' in runtime
assert 'insertContiguousSpecifiers:navigation atIndex:insertionIndex animated:NO' in runtime
assert 'haoge_settingsshelf_navigationInsertionIndex([root specifiers])' in runtime
assert 'haoge_settingsshelf_rootRemovalRanges' in runtime
assert 'addSpecifiersFromArray:missingNavigation' not in runtime
grouping=(root/'Sources/HaogeSettingsShelfGrouping.m').read_text()
assert 'haoge_settingsshelf_navigationInsertionIndex(kept)' in grouping
assert 'haoge_settingsshelf_isSelfEntry(entry)' in grouping
assert not list((root/'layout').rglob('*.plist'))
assert not (root/'HaogeSettingsShelfPrefs/HaogeSettingsShelfRootListController.m').exists()
custom=(root/'Sources/HaogeSettingsShelfCustomization.m').read_text()
assert '@[@"navigation", @"tweaks", @"apps"]' not in custom
assert 'haoge_settingsshelf_fitIcon' in custom
assert 'haoge_settingsshelf_originalIconSize' in custom
assert 'if (!apps) haoge_settingsshelf_categoryApply(entry)' in category
assert 'for (id row in state.haoge_settingsshelf_apps)' not in runtime
assert 'if ([controller isViewLoaded]) { haoge_settingsshelf_schedule(controller); return rows; }' in runtime
assert '_insertContiguousSpecifiers:atIndex:animated:' in runtime
# Preserve system insertion arguments, then reconcile through PSListController APIs.
assert 'original)(controller, insertSelector, rows, index, animated);' in runtime
assert 'MAX(0, MIN(index' not in runtime
assert 'haoge_settingsshelf_schedule(controller);' in runtime
assert 'PREFERENCES' not in (root/'Makefile').read_text()
assert (root/'.github/workflows/build.yml').is_file()
assert 'Name: 插件收纳' in control
assert json.loads((root/'tweak.json').read_text())['display_name']=='插件收纳'
hook=runtime
assert '@"越狱插件"' in hook and '@"应用软件"' in hook
assert '@"应用设置"' not in hook
for filename in ('HaogeSettingsShelfApps@2x.png','HaogeSettingsShelfTweaks@2x.png'):
    data=(root/'HaogeSettingsShelfPrefs/Resources'/filename).read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    assert struct.unpack_from('>II',data,16)==(60,60)
    assert filename in hook
subprocess.run(['sh','-n',str(root/'build.sh')],check=True)
print(json.dumps({'plists':'all valid','package':'com.haoge.settingsshelf','filter':['com.apple.Preferences'],'always_on':True,'legacy_switch_ignored':True,'grouping_model':'present','delayed_insertion_hook':'present','navigation':'between account and connectivity','live_table_updates':'native remove/insert only','initial_array_transform':'before view loaded only','shell_build_script':'syntax-ok','theos_link_or_package_build':False},indent=2))
