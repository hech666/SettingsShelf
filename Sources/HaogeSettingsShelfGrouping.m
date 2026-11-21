#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfSnapshot.h"

@protocol HaogeSettingsShelfEntry <NSObject>
- (NSString *)identifier;
- (NSInteger)cellType;
- (id)propertyForKey:(NSString *)key;
@end

static NSString *haoge_settingsshelf_identifier(id entry) {
    id value = [entry respondsToSelector:@selector(identifier)] ? [(id<HaogeSettingsShelfEntry>)entry identifier] : nil;
    return [value isKindOfClass:NSString.class] ? value : @"";
}
BOOL haoge_settingsshelf_isNavigation(id entry) {
    return [haoge_settingsshelf_identifier(entry) hasPrefix:@"com.haoge.settingsshelf.category."];
}
static BOOL haoge_settingsshelf_isGroup(id entry) {
    return [entry respondsToSelector:@selector(cellType)] && [(id<HaogeSettingsShelfEntry>)entry cellType] == 0;
}
NSInteger haoge_settingsshelf_entryCategory(id object) {
    if (haoge_settingsshelf_isNavigation(object) || haoge_settingsshelf_isGroup(object) ||
        ![object respondsToSelector:@selector(propertyForKey:)]) return 0;
    id<HaogeSettingsShelfEntry> entry = object;
    for (NSString *key in @[@"AppBundleID", @"appIDForLazyIcon", @"applicationBundleIdentifier"]) {
        id value = [entry propertyForKey:key];
        if ([value isKindOfClass:NSString.class] && [value length] && ![value hasPrefix:@"com.apple."]) return 2;
    }
    for (NSString *key in @[@"lazy-bundle", @"bundlePath", @"bundle"]) {
        id value = [entry propertyForKey:key];
        NSString *path = [value isKindOfClass:NSBundle.class] ? [value bundlePath] :
            ([value isKindOfClass:NSString.class] ? value : nil);
        if (!path.length || [path hasPrefix:@"/System/"] || [path containsString:@"/System/Library/"]) continue;
        if ([path containsString:@"/Library/PreferenceBundles/"]) return 1;
        if ([key isEqualToString:@"lazy-bundle"]) return 1;
    }
    return 0;
}

static NSString *haoge_settingsshelf_anchorIdentifier(id row) {
    NSString *identifier = haoge_settingsshelf_identifier(row);
    if (!identifier.length && [row respondsToSelector:@selector(propertyForKey:)]) {
        id value = [(id<HaogeSettingsShelfEntry>)row propertyForKey:@"id"];
        if ([value isKindOfClass:NSString.class]) identifier = value;
    }
    return [[identifier.lowercaseString componentsSeparatedByCharactersInSet:
        NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
}
NSUInteger haoge_settingsshelf_navigationInsertionIndex(NSArray *rows) {
    NSUInteger section = NSNotFound, account = NSNotFound;
    for (NSUInteger i = 0; i < rows.count; ++i) {
        id row = rows[i];
        if (haoge_settingsshelf_isGroup(row)) { section = i; continue; }
        NSString *identifier = haoge_settingsshelf_anchorIdentifier(row);
        if ([@[@"appleaccount", @"appleid", @"appleaccountcell", @"appleidaccount"] containsObject:identifier]) account = i;
        if ([@[@"airplanemode", @"wifi", @"wifisettings", @"bluetooth", @"mobiledata", @"mobiledatasettingsid"] containsObject:identifier]) {
            // Do not move the system rows or split the normal network section.
            // A missing group header falls back to the first connectivity row.
            return section != NSNotFound && (account == NSNotFound || section > account) ? section : i;
        }
    }
    if (account != NSNotFound) {
        for (NSUInteger i = account + 1; i < rows.count; ++i)
            if (haoge_settingsshelf_isGroup(rows[i])) return i;
        return rows.count;
    }
    return 0;
}

static BOOL haoge_settingsshelf_isSelfEntry(id row) {
    if (haoge_settingsshelf_isNavigation(row)) return NO;
    NSString *identifier = haoge_settingsshelf_identifier(row).lowercaseString;
    if ([@[@"settingsshelf", @"com.haoge.settingsshelf", @"haogesettingsshelfprefs"] containsObject:identifier]) return YES;
    if (![row respondsToSelector:@selector(propertyForKey:)]) return NO;
    for (NSString *key in @[@"lazy-bundle", @"bundlePath", @"bundle"]) {
        id value = [(id<HaogeSettingsShelfEntry>)row propertyForKey:key];
        NSString *path = [value isKindOfClass:NSBundle.class] ? [value bundlePath] :
            ([value isKindOfClass:NSString.class] ? value : nil);
        if ([path.lastPathComponent isEqualToString:@"HaogeSettingsShelfPrefs.bundle"] ||
            [path isEqualToString:@"HaogeSettingsShelfPrefs"]) return YES;
    }
    id detail = [(id<HaogeSettingsShelfEntry>)row propertyForKey:@"detail"];
    return [detail isKindOfClass:NSString.class] && [detail isEqualToString:@"HaogeSettingsShelfRootListController"];
}

NSArray<NSValue *> *haoge_settingsshelf_rootRemovalRanges(
    NSArray *current, NSArray *desired, NSArray *navigation, BOOL *insertNavigation) {
    NSMutableArray *retained = [NSMutableArray array];
    for (id row in current)
        if (!haoge_settingsshelf_isNavigation(row) && [desired indexOfObjectIdenticalTo:row] != NSNotFound) [retained addObject:row];
    NSUInteger target = haoge_settingsshelf_navigationInsertionIndex(retained);
    NSUInteger keepStart = NSNotFound, prefix = 0;
    for (NSUInteger i = 0; i < current.count; ++i) {
        if (navigation.count == 3 && prefix == target && current.count - i >= navigation.count &&
            current[i] == navigation[0] && current[i + 1] == navigation[1] && current[i + 2] == navigation[2]) {
            keepStart = i; break;
        }
        if (!haoge_settingsshelf_isNavigation(current[i]) && [desired indexOfObjectIdenticalTo:current[i]] != NSNotFound) ++prefix;
    }
    if (insertNavigation) *insertNavigation = navigation.count == 3 && keepStart == NSNotFound;
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSInteger start = -1;
    for (NSUInteger i = 0; i <= current.count; ++i) {
        BOOL remove = NO;
        if (i < current.count) {
            id row = current[i];
            remove = [desired indexOfObjectIdenticalTo:row] == NSNotFound ||
                (haoge_settingsshelf_isNavigation(row) &&
                 (keepStart == NSNotFound || i < keepStart || i - keepStart >= navigation.count));
        }
        if (remove && start < 0) start = (NSInteger)i;
        if (!remove && start >= 0) {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, i - (NSUInteger)start)]];
            start = -1;
        }
    }
    return ranges;
}

// Category scope separates an app from a tweak using the same identifier.
// An identifier-free row is keyed by its host-provided source, never its
// display name (which can change after customization).
static NSString *haoge_settingsshelf_observationKey(id<HaogeSettingsShelfEntry> row, NSInteger category) {
    NSString *identifier = haoge_settingsshelf_identifier(row);
    if (identifier.length) return [@"id:" stringByAppendingString:identifier];
    NSArray *keys = category == 1 ? @[@"lazy-bundle", @"bundlePath", @"bundle"] :
        @[@"AppBundleID", @"appIDForLazyIcon", @"applicationBundleIdentifier"];
    for (NSString *key in keys) {
        id value = [row propertyForKey:key];
        if ([value isKindOfClass:NSBundle.class]) value = [value bundlePath];
        if (![value isKindOfClass:NSString.class] || ![value length]) continue;
        if (category == 1 && ([value hasPrefix:@"/System/"] || [value containsString:@"/System/Library/"] ||
            (![key isEqualToString:@"lazy-bundle"] && ![value containsString:@"/Library/PreferenceBundles/"]))) continue;
        if (category == 2 && [value hasPrefix:@"com.apple."]) continue;
        return [@"source:" stringByAppendingString:value];
    }
    return nil;
}

@implementation HaogeSettingsShelfGroupingState {
    NSMutableOrderedSet<NSString *> *_haoge_settingsshelf_tweakKeys;
    NSMutableOrderedSet<NSString *> *_haoge_settingsshelf_appKeys;
    NSMutableDictionary<NSString *, id> *_haoge_settingsshelf_tweakRows;
    NSMutableDictionary<NSString *, id> *_haoge_settingsshelf_appRows;
}
- (instancetype)init {
    if ((self = [super init])) {
        _haoge_settingsshelf_tweakKeys = [NSMutableOrderedSet orderedSet];
        _haoge_settingsshelf_appKeys = [NSMutableOrderedSet orderedSet];
        _haoge_settingsshelf_tweakRows = [NSMutableDictionary dictionary];
        _haoge_settingsshelf_appRows = [NSMutableDictionary dictionary];
        _haoge_settingsshelf_tweaks = @[];
        _haoge_settingsshelf_apps = @[];
    }
    return self;
}
- (BOOL)haoge_settingsshelf_capture:(NSArray *)rows {
    if (![rows isKindOfClass:NSArray.class]) return NO;
    BOOL changedTweaks = NO, changedApps = NO;
    // There is no reliable full-inventory marker: even an array without our
    // navigation may be a partial reload. Retain observations for this root only.
    for (id row in rows) {
        if (haoge_settingsshelf_isSelfEntry(row)) continue;
        NSInteger category = haoge_settingsshelf_entryCategory(row);
        if (!category) continue;
        NSString *key = haoge_settingsshelf_observationKey(row, category);
        if (!key.length) continue;
        NSMutableOrderedSet *keys = category == 1 ? _haoge_settingsshelf_tweakKeys : _haoge_settingsshelf_appKeys;
        NSMutableDictionary *entries = category == 1 ? _haoge_settingsshelf_tweakRows : _haoge_settingsshelf_appRows;
        if (entries[key] == row) continue;
        [keys addObject:key];
        entries[key] = row;
        if (category == 1) changedTweaks = YES; else changedApps = YES;
    }
    NSArray *tweaks = changedTweaks ? [_haoge_settingsshelf_tweakRows objectsForKeys:_haoge_settingsshelf_tweakKeys.array notFoundMarker:NSNull.null] : _haoge_settingsshelf_tweaks;
    NSArray *apps = changedApps ? [_haoge_settingsshelf_appRows objectsForKeys:_haoge_settingsshelf_appKeys.array notFoundMarker:NSNull.null] : _haoge_settingsshelf_apps;
    changedTweaks = !haoge_settingsshelf_sameRows(_haoge_settingsshelf_tweaks, tweaks);
    changedApps = !haoge_settingsshelf_sameRows(_haoge_settingsshelf_apps, apps);
    if (changedTweaks) _haoge_settingsshelf_tweaks = [tweaks copy];
    if (changedApps) _haoge_settingsshelf_apps = [apps copy];
    return changedTweaks || changedApps;
}
- (NSArray *)haoge_settingsshelf_transform:(NSArray *)input enabled:(BOOL)enabled navigation:(NSArray *)navigation {
    if (![input isKindOfClass:NSArray.class]) return input;
    [self haoge_settingsshelf_capture:input];
    if (!enabled || navigation.count != 3) return input;
    NSMutableArray *kept = [NSMutableArray array];
    id pendingGroup = nil;
    BOOL groupHadMoved = NO;
    // System rows and their order are drawn only from the current host list.
    // Suppress a group only if its current rows all moved out of the root.
    for (id entry in input) {
        if (haoge_settingsshelf_isNavigation(entry)) continue;
        if (haoge_settingsshelf_isGroup(entry)) {
            if (pendingGroup && !groupHadMoved) [kept addObject:pendingGroup];
            pendingGroup = entry; groupHadMoved = NO;
        } else if (haoge_settingsshelf_isSelfEntry(entry) || haoge_settingsshelf_entryCategory(entry)) {
            groupHadMoved = YES;
        } else {
            if (pendingGroup) { [kept addObject:pendingGroup]; pendingGroup = nil; }
            [kept addObject:entry];
        }
    }
    if (pendingGroup && !groupHadMoved) [kept addObject:pendingGroup];
    NSMutableArray *result = [kept mutableCopy];
    NSUInteger index = haoge_settingsshelf_navigationInsertionIndex(kept);
    [result insertObjects:navigation atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, navigation.count)]];
    return [result copy];
}
@end
