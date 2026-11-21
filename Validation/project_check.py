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
assert 'reloadData' not in runtime and 'reloadData' not in category
assert 'setSpecifiers:' not in category
assert runtime.index('haoge_settingsshelf_captureRows(controller, rows);') < runtime.index('if (haoge_settingsshelf_busy) return rows;')
assert 'HAOGE_SETTINGSSHELF_SNAPSHOT_CHANGED_NOTIFICATION' in runtime and 'HAOGE_SETTINGSSHELF_SNAPSHOT_CHANGED_NOTIFICATION' in category
assert 'if (!_haoge_settingsshelf_visible) return;' in category
assert 'haoge_settingsshelf_sameRows(_haoge_settingsshelf_renderedItems, items)' in category
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
shared_build=(root/'HaogeSettingsShelfBuild.mk').read_text()
assert [line.strip() for line in shared_build.splitlines() if line.strip().startswith('ARCHS')] == ['ARCHS = arm64e']
assert not any(line.strip().startswith('ARCHS') for line in (root/'Makefile').read_text().splitlines())
assert not any(line.strip().startswith('ARCHS') for line in (root/'HaogeSettingsShelfPrefs/Makefile').read_text().splitlines())
assert 'include HaogeSettingsShelfBuild.mk' in (root/'Makefile').read_text()
assert 'include ../HaogeSettingsShelfBuild.mk' in (root/'HaogeSettingsShelfPrefs/Makefile').read_text()
# PreferenceLoader inventory is independent of root partial-list observations.
inventory=(root/'Sources/HaogeSettingsShelfInventory.m').read_text()
assert 'haoge_settingsshelf_tweakInventoryForController' in runtime and 'haoge_settingsshelf_tweakInventoryForController' in category
assert '[self haoge_settingsshelf_categoryItems]' in category
assert '/Library/PreferenceLoader/Preferences' in runtime
assert '/Library/PreferenceBundles' in runtime and '/System/Library/PreferenceBundles' in runtime
assert 'enumeratorAtURL:rootURL' in inventory
assert 'CoreFoundationVersion' in inventory and 'current < upper' in inventory
assert 'source[@"filter"] ?: source[@"pl_filter"]' in inventory
assert 'entry[@"pl_filter"]' in inventory
assert 'HaogeSettingsShelfPrefs.bundle' in inventory
assert 'localizedCaseInsensitiveCompare' in inventory
assert 'SpecifiersFromPlist' in runtime and 'NSMutableArray *__strong *' in runtime
assert 'generate(input, nil, controller, filename, bundle, nil, nil, controller, &retained)' in runtime
assert '@{@"items":@[item]}' in runtime
assert 'forKey:PSLazilyLoadedBundleKey' in runtime
assert '[item removeObjectForKey:' not in runtime and '[item setObject:' not in runtime
assert 'haoge_settingsshelf_inventoryRowsForOwner' in runtime
assert 'owner && owner == requester' in inventory
assert 'if (![NSThread isMainThread] || !controller) return @[];' in runtime
assert 'return haoge_settingsshelf_inventoryRows ?: @[]' not in runtime
assert 'haoge_settingsshelf_inventoryRowsDescriptors isEqualToArray:' in runtime
assert 'haoge_settingsshelf_inventoryController = nil' not in runtime
assert 'HaogeSettingsShelfInventoryRetainedKey' not in runtime
workflow=(root/'.github/workflows/build.yml').read_text()
for regression in ('InventoryTests.m','GroupingTests.m','TopPlacementTests.m','GuardTests.m','AccountPlacementTests.m','CustomizationScopeTests.m'):
    assert regression in workflow, regression
subprocess.run(['sh','-n',str(root/'build.sh')],check=True)
print(json.dumps({'plists':'all valid','package':'com.haoge.settingsshelf','filter':['com.apple.Preferences'],'always_on':True,'legacy_switch_ignored':True,'grouping_model':'present','delayed_insertion_hook':'present','navigation':'between account and connectivity','live_table_updates':'native remove/insert only','initial_array_transform':'before view loaded only','shell_build_script':'syntax-ok','theos_link_or_package_build':False},indent=2))
