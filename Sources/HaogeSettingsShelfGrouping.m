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

NSArray<NSValue *> *haoge_settingsshelf_rootRemovalRanges(
    NSArray *current, NSArray *desired, NSArray *navigation, BOOL *insertNavigation) {
    BOOL navigationAtTop = navigation.count == 3 && current.count >= navigation.count;
    for (NSUInteger i = 0; navigationAtTop && i < navigation.count; ++i) {
        if (current[i] != navigation[i]) navigationAtTop = NO;
    }
    if (insertNavigation) *insertNavigation = !navigationAtTop;
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSInteger start = -1;
    for (NSUInteger i = 0; i <= current.count; ++i) {
        BOOL remove = NO;
        if (i < current.count) {
            id row = current[i];
            remove = [desired indexOfObjectIdenticalTo:row] == NSNotFound ||
                (haoge_settingsshelf_isNavigation(row) && (!navigationAtTop || i >= navigation.count));
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
    NSMutableArray *kept = [NSMutableArray array];
    id pendingGroup = nil; BOOL groupHadMoved = NO; NSUInteger keptSinceGroup = 0;
    for (id entry in raw) {
        if (haoge_settingsshelf_isGroup(entry)) {
            if (pendingGroup && (!groupHadMoved || keptSinceGroup)) [kept addObject:pendingGroup];
            pendingGroup = entry; groupHadMoved = NO; keptSinceGroup = 0;
            continue;
        }
        NSInteger category = haoge_settingsshelf_entryCategory(entry);
        if (category) {
            [category == 1 ? tweaks : apps addObject:entry]; groupHadMoved = YES;
        } else {
            if (pendingGroup) { [kept addObject:pendingGroup]; pendingGroup = nil; }
            [kept addObject:entry]; ++keptSinceGroup;
        }
    }
    if (pendingGroup && !groupHadMoved) [kept addObject:pendingGroup];
    self.haoge_settingsshelf_tweaks = tweaks; self.haoge_settingsshelf_apps = apps;
    return [navigation arrayByAddingObjectsFromArray:kept];
}
@end
