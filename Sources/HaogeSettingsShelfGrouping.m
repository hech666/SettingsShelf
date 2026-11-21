#import "HaogeSettingsShelfGrouping.h"

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

static BOOL haoge_settingsshelf_sameEntry(id left, id right) {
    if (left == right) return YES;
    NSString *a = haoge_settingsshelf_identifier(left), *b = haoge_settingsshelf_identifier(right);
    return a.length && [a isEqualToString:b];
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

@implementation HaogeSettingsShelfGroupingState
- (instancetype)init {
    if ((self = [super init])) {
        _haoge_settingsshelf_raw = @[]; _haoge_settingsshelf_tweaks = @[]; _haoge_settingsshelf_apps = @[];
    }
    return self;
}
- (NSArray *)haoge_settingsshelf_transform:(NSArray *)input enabled:(BOOL)enabled navigation:(NSArray *)navigation {
    if (![input isKindOfClass:NSArray.class]) return input;
    BOOL alreadyGrouped = NO;
    for (id entry in input) if (haoge_settingsshelf_isNavigation(entry)) { alreadyGrouped = YES; break; }
    NSMutableArray *raw = alreadyGrouped ? [self.haoge_settingsshelf_raw mutableCopy] : [NSMutableArray array];
    for (id entry in input) {
        if (haoge_settingsshelf_isNavigation(entry)) continue;
        NSUInteger found = NSNotFound;
        for (NSUInteger i = 0; i < raw.count; ++i) if (haoge_settingsshelf_sameEntry(raw[i], entry)) { found = i; break; }
        if (found == NSNotFound) [raw addObject:entry]; else raw[found] = entry;
    }
    self.haoge_settingsshelf_raw = raw;
    if (!enabled || navigation.count != 3) return [raw copy];
    NSMutableArray *tweaks = [NSMutableArray array], *apps = [NSMutableArray array];
    for (id entry in raw) {
        if (haoge_settingsshelf_isSelfEntry(entry)) continue;
        NSInteger category = haoge_settingsshelf_entryCategory(entry);
        if (category) [category == 1 ? tweaks : apps addObject:entry];
    }
    NSMutableArray *kept = [NSMutableArray array];
    id pendingGroup = nil; BOOL groupHadMoved = NO; NSUInteger keptSinceGroup = 0;
    // Only the third-party buckets are historical. System order and membership
    // always come from the current host snapshot, including a late Apple ID.
    for (id entry in alreadyGrouped ? input : raw) {
        if (haoge_settingsshelf_isNavigation(entry)) continue;
        if (haoge_settingsshelf_isGroup(entry)) {
            if (pendingGroup && (!groupHadMoved || keptSinceGroup)) [kept addObject:pendingGroup];
            pendingGroup = entry; groupHadMoved = NO; keptSinceGroup = 0;
            continue;
        }
        if (haoge_settingsshelf_isSelfEntry(entry)) { groupHadMoved = YES; continue; }
        NSInteger category = haoge_settingsshelf_entryCategory(entry);
        if (category) {
            groupHadMoved = YES;
        } else {
            if (pendingGroup) { [kept addObject:pendingGroup]; pendingGroup = nil; }
            [kept addObject:entry]; ++keptSinceGroup;
        }
    }
    if (pendingGroup && !groupHadMoved) [kept addObject:pendingGroup];
    self.haoge_settingsshelf_tweaks = tweaks; self.haoge_settingsshelf_apps = apps;
    NSMutableArray *result = [kept mutableCopy];
    NSUInteger index = haoge_settingsshelf_navigationInsertionIndex(kept);
    [result insertObjects:navigation atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, navigation.count)]];
    return [result copy];
}
@end
