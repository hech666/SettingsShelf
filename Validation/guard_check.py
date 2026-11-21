#!/usr/bin/env python3
"""Source/fixture regression checks; NOT a substitute for GuardTests/iOS UI tests.
Usage: python3 Validation/guard_check.py [path/to/settingsshelf_cloud]
"""
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
fixtures = Path(sys.argv[1]) if len(sys.argv) > 1 else root.parent / 'settingsshelf_cloud'
guards = (root / 'Sources/HaogeSettingsShelfGuards.m').read_text()
header = (root / 'Sources/HaogeSettingsShelfGuards.h').read_text()
prefs = (root / 'Sources/HaogeSettingsShelfPreferences.h').read_text()
runtime = (root / 'Sources/HaogeSettingsShelfRuntime.m').read_text()
category = (root / 'HaogeSettingsShelfPrefs/HaogeSettingsShelfCategoryListController.m').read_text()
tests = (root / 'Validation/GuardTests.m').read_text()
checks = []
def check(label, condition):
    if not condition:
        raise AssertionError(label)
    checks.append(label)

def strings(function):
    body = guards.split(function + '(void) {', 1)[1].split('\n}', 1)[0]
    return re.findall(r'@"([^"\\]*)"', body)

constants = json.loads((fixtures / 'GuardConstants.json').read_text())
for func, fixture in [('repairPropertyKeys','repairKeys'), ('repairTerms','repairTerms'),
                      ('addItemAccessorKeys','itemAccessors'), ('updatePropertyKeys','updateKeys')]:
    actual = strings('haoge_settingsshelf_' + func)
    check('fixture constants: ' + fixture,
          [s.lower() for s in actual] == [s.lower() for s in constants[fixture]])
methods = json.loads((fixtures / 'BatteryUsageUI.methods.json').read_text())
for name, encoding in [('genuineBatteryStatus','i16@0:8'),
                       ('getBatteryHealthServiceState','i16@0:8'),
                       ('getBatteryServiceSuggestion','@16@0:8')]:
    check('observed ABI: ' + name, any(m['name'] == name and m['encoding'] == encoding for m in methods))
check('observed noarg selector installed', 'SEL suggestion = NSSelectorFromString(@"getBatteryServiceSuggestion");' in guards)
check('noarg replacement ABI', bool(re.search(r'installMethod\(batteryMeta, suggestion, \(IMP\)haoge_settingsshelf_healthSpecifiersHook,\s*2, \'@\', NULL\)', guards)))
check('legacy selector separately gated', 'installMethod(batteryMeta, legacySuggestion' in guards)
for code in 'cCsSiIlLqQB':
    check('integer return ABI: ' + code, "case '%s': return (IMP)haoge_settingsshelf_status_%s;" % (code, code) in guards)
for key in ('suppressBatteryServiceWarnings', 'suppressSoftwareUpdatePrompt'):
    check('preference read: ' + key, 'preferenceBool(@"' + key + '")' in guards)
    check('panel switch: ' + key, 'key:@"' + key + '"' in category)
check('missing preferences default off', ': NO;' in prefs.split('static inline BOOL haoge_settingsshelf_preferenceBool', 1)[1].split('\n}', 1)[0])
check('flags initialized off', guards.count('ATOMIC_VAR_INIT(false)') == 2)
check('disabled rows preserve identity', '(!repair && !update)) return rows;' in guards)
check('filter never edits source array', '[rows mutableCopy]' in guards and '[filtered removeObjectsAtIndexes:removals]' in guards)
check('own navigation retained', 'haoge_settingsshelf_isOwnNavigation(row) || haoge_settingsshelf_isGroupRow(row)' in guards)
check('mixed headers retained', 'end - i - 1)' in guards and 'countOfIndexesInRange:' in guards)
check('guard module does not hook PSListController', 'PSListController' not in guards)
check('guard module does not replace specifiers', 'setSpecifiers:' not in guards and 'reloadData' not in guards)
check('hook signature validates arity', 'method_getNumberOfArguments(method) != arguments' in guards)
check('hook signature validates return', 'haoge_settingsshelf_returnCode(method) != returnCode' in guards)
check('hook signature validates argument', 'haoge_settingsshelf_argumentCode(method, 2) != *arg2Code' in guards)
check('installation serialized', '@synchronized (haoge_settingsshelf_guardLock)' in guards)
check('duplicate installs return before hooking', guards.index('containsObject:key]) return YES') < guards.index('MSHookMessageEx(target'))
check('original IMP retained', 'if (!original) original = prior;' in guards)
check('root transform integration', 'return haoge_settingsshelf_guardRootRows(desired);' in runtime)
check('runtime root-only reconciliation', '!haoge_settingsshelf_isRoot(root)' in runtime)
check('live table uses native removal', '[root removeContiguousSpecifiers:run animated:NO]' in runtime)
check('notifications rebuild original source', 'if (root && !haoge_settingsshelf_busy) [root reloadSpecifiers];' in runtime)
check('refresh precedes rebuild', runtime.index('haoge_settingsshelf_installGuards();', runtime.index('static void haoge_settingsshelf_preferencesChanged')) < runtime.index('if (root && !haoge_settingsshelf_busy) [root reloadSpecifiers]'))
check('Darwin notification sent', 'CFNotificationCenterPostNotification' in category)
check('Darwin notification observed', 'CFNotificationCenterAddObserver' in runtime)
check('native regressions cover repeated toggles', 'i < 100' in tests)
check('native regressions reject double-return ABI', '- (double)isValidCAA:' in tests)
check('native regressions cover off-state original results', 'genuineBatteryStatus] == -7' in tests)
check('noarg native regression', 'getBatteryServiceSuggestion] == nil' in tests)
check('public API unchanged', header.count('FOUNDATION_EXPORT') == 3)
print(json.dumps({'status':'PASS', 'source_checks':len(checks), 'checks':checks,
                  'guards_sha256':hashlib.sha256(guards.encode()).hexdigest(),
                  'native_runtime_executed':False, 'ios_executed':False}, indent=2, ensure_ascii=False))
