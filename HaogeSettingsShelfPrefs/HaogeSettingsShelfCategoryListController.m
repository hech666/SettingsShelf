#import "HaogeSettingsShelfCategoryListController.h"
#import <dlfcn.h>

static NSString * const HaogeSettingsShelfCategoryKey = @"HaogeSettingsShelfCategory";
static NSString * const HaogeSettingsShelfAppBundleIDKey = @"AppBundleID";

@implementation HaogeSettingsShelfCategoryListController

- (NSArray *)haoge_settingsshelf_candidatesAtPath:(NSString *)path {
    NSError *error = nil;
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (![names isKindOfClass:[NSArray class]]) return @[];
    return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSString *)haoge_settingsshelf_bundlePathForEntry:(NSDictionary *)entry {
    NSString *explicitPath = entry[@"bundlePath"];
    if ([explicitPath isKindOfClass:[NSString class]] && explicitPath.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:explicitPath]) return explicitPath;
    NSString *bundleName = entry[@"bundle"];
    if (![bundleName isKindOfClass:[NSString class]] || bundleName.length == 0) return nil;
    if ([bundleName hasSuffix:@".bundle"]) bundleName = [bundleName stringByDeletingPathExtension];
    NSArray *roots = @[@"/Library/PreferenceBundles", @"/System/Library/PreferenceBundles"];
    for (NSString *root in roots) {
        NSString *resolvedRoot = [root hasPrefix:@"/System/"] ? root : haoge_settingsshelf_resourcePath(root);
        NSString *candidate = [resolvedRoot stringByAppendingPathComponent:
            [bundleName stringByAppendingPathExtension:@"bundle"]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

- (NSString *)haoge_settingsshelf_appBundleIDFromPlist:(NSDictionary *)plist entry:(NSDictionary *)entry {
    id value = entry[HaogeSettingsShelfAppBundleIDKey] ?: plist[HaogeSettingsShelfAppBundleIDKey];
    if (![value isKindOfClass:[NSString class]]) {
        id rawFilter = plist[@"filter"] ?: plist[@"pl_filter"];
        NSDictionary *filter = [rawFilter isKindOfClass:[NSDictionary class]] ? rawFilter : nil;
        value = filter[HaogeSettingsShelfAppBundleIDKey];
    }
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (PSSpecifier *)haoge_settingsshelf_specifierForEntry:(NSDictionary *)entry title:(NSString *)title {
    NSString *detailName = entry[@"detail"];
    NSString *bundleName = entry[@"bundle"];
    if (![detailName isKindOfClass:[NSString class]] || detailName.length == 0 ||
        ![bundleName isKindOfClass:[NSString class]] || bundleName.length == 0) return nil;
    NSString *bundlePath = [self haoge_settingsshelf_bundlePathForEntry:entry];
    if (!bundlePath) return nil;
    if (![title isKindOfClass:[NSString class]] || title.length == 0) return nil;
    id rawIdentifier = entry[@"id"];
    NSString *identifier = [rawIdentifier isKindOfClass:[NSString class]] && [rawIdentifier length] > 0
        ? rawIdentifier : [bundleName stringByAppendingFormat:@".%@", detailName];

    NSBundle *childBundle = [NSBundle bundleWithPath:bundlePath];
    if (!childBundle) return nil;
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
        target:nil set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
    specifier.identifier = identifier;
    specifier.name = title;
    [specifier setProperty:detailName forKey:@"detail"];
    [specifier setProperty:bundleName forKey:@"bundle"];
    [specifier setProperty:bundlePath forKey:@"lazy-bundle"];
    [specifier setProperty:@YES forKey:@"isController"];
    [specifier setProperty:identifier forKey:@"id"];

    NSString *iconName = entry[@"icon"];
    if ([iconName isKindOfClass:[NSString class]] && iconName.length > 0) {
        NSString *iconPath = [bundlePath stringByAppendingPathComponent:iconName];
        UIImage *image = [UIImage imageWithContentsOfFile:iconPath];
        if (image) [specifier setProperty:image forKey:@"iconImage"];
    }
    return specifier;
}

- (void)haoge_settingsshelf_appendPlistEntriesTo:(NSMutableArray<PSSpecifier *> *)rows
                                         appsOnly:(BOOL)appsOnly {
    NSString *directory = haoge_settingsshelf_resourcePath(@"/Library/PreferenceLoader/Preferences");
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (PSSpecifier *existing in rows) if (existing.identifier.length) [seen addObject:existing.identifier];
    for (NSString *filename in [self haoge_settingsshelf_candidatesAtPath:directory]) {
        if ([[filename pathExtension] caseInsensitiveCompare:@"plist"] != NSOrderedSame) continue;
        NSString *path = [directory stringByAppendingPathComponent:filename];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
        NSDictionary *entry = [plist[@"entry"] isKindOfClass:[NSDictionary class]] ? plist[@"entry"] : nil;
        if (!entry) continue;
        NSString *bundleName = entry[@"bundle"];
        if ([bundleName isKindOfClass:[NSString class]] && [bundleName hasPrefix:@"HaogeSettingsShelf"]) continue;
        NSString *appBundleID = [self haoge_settingsshelf_appBundleIDFromPlist:plist entry:entry];
        if (appsOnly != (appBundleID.length > 0)) continue;
        if (![entry[@"detail"] isKindOfClass:[NSString class]] ||
            ![entry[@"bundle"] isKindOfClass:[NSString class]]) continue;
        if (![manager fileExistsAtPath:[self haoge_settingsshelf_bundlePathForEntry:entry] ?: @""]) continue;
        NSString *title = entry[@"label"] ?: filename.stringByDeletingPathExtension;
        PSSpecifier *specifier = [self haoge_settingsshelf_specifierForEntry:entry title:title];
        if (!specifier || [seen containsObject:specifier.identifier]) continue;
        [seen addObject:specifier.identifier];
        [rows addObject:specifier];
    }
}

- (NSMutableArray<PSSpecifier *> *)haoge_settingsshelf_appProviderSpecifiers {
    NSMutableArray<PSSpecifier *> *rows = [NSMutableArray array];
    NSArray *symbols = @[@"haoge_settingsshelf_appsSpecifiers", @"THAppsSpecifiers"];
    for (NSString *name in symbols) {
        void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
        if (!symbol) continue;
        NSArray *(*provider)(void) = (NSArray *(*)(void))symbol;
        id result = provider();
        if (![result isKindOfClass:[NSArray class]]) continue;
        for (id item in result) if ([item isKindOfClass:[PSSpecifier class]]) [rows addObject:item];
        if (rows.count) break;
    }
    return rows;
}

- (NSMutableArray *)haoge_settingsshelf_buildSpecifiers {
    BOOL appsOnly = [[self.specifier propertyForKey:HaogeSettingsShelfCategoryKey] isEqual:@"apps"];
    NSString *heading = appsOnly ? @"应用软件" : @"越狱插件";
    NSMutableArray *rows = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:heading]];
    if (appsOnly) [rows addObjectsFromArray:[self haoge_settingsshelf_appProviderSpecifiers]];
    [self haoge_settingsshelf_appendPlistEntriesTo:rows appsOnly:appsOnly];
    if (rows.count == 1) {
        NSString *message = appsOnly ? @"暂无可用的应用软件项" : @"未找到可用的插件设置项";
        PSSpecifier *empty = [PSSpecifier preferenceSpecifierNamed:message
            target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
        [empty setProperty:message forKey:@"staticTextMessage"];
        [rows addObject:empty];
    }
    return rows;
}

- (NSMutableArray *)specifiers {
    if (!_specifiers) _specifiers = [self haoge_settingsshelf_buildSpecifiers];
    return _specifiers;
}

@end
