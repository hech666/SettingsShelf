#import "HaogeSettingsShelfInventory.h"
#import <CoreFoundation/CoreFoundation.h>

static BOOL haoge_settingsshelf_inventoryFilterAllows(id filter) {
    if (!filter) return YES;
    if (![filter isKindOfClass:NSDictionary.class]) return NO;
    id range = filter[@"CoreFoundationVersion"];
    if (!range) return YES;
    if (![range isKindOfClass:NSArray.class]) return NO;
    if ([range count] == 0) return YES;
    if (![range[0] respondsToSelector:@selector(doubleValue)]) return NO;
    double current = kCFCoreFoundationVersionNumber;
    double lower = [range[0] doubleValue];
    if ([range count] == 1) return lower <= current;
    if (![range[1] respondsToSelector:@selector(doubleValue)]) return NO;
    double upper = [range[1] doubleValue];
    return lower <= current && current < upper;
}

static BOOL haoge_settingsshelf_directoryExists(NSString *path) {
    BOOL directory = NO;
    return path.length && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory;
}

static NSString *haoge_settingsshelf_resolvedBundlePath(NSDictionary *entry,
    NSString *preferenceBundlesDirectory, NSString *systemPreferenceBundlesDirectory) {
    NSString *explicitPath = [entry[@"bundlePath"] isKindOfClass:NSString.class] ? entry[@"bundlePath"] : nil;
    if (haoge_settingsshelf_directoryExists(explicitPath)) return explicitPath;
    NSString *bundle = [entry[@"bundle"] isKindOfClass:NSString.class] ? entry[@"bundle"] : nil;
    if (!bundle.length) return nil;
    NSString *bundleName = [bundle.lastPathComponent stringByDeletingPathExtension];
    if (!bundleName.length) return nil;
    NSString *relative = [bundleName stringByAppendingPathExtension:@"bundle"];
    NSString *path = [preferenceBundlesDirectory stringByAppendingPathComponent:relative];
    if (haoge_settingsshelf_directoryExists(path)) return path;
    path = [systemPreferenceBundlesDirectory stringByAppendingPathComponent:relative];
    return haoge_settingsshelf_directoryExists(path) ? path : nil;
}

static NSComparisonResult haoge_settingsshelf_descriptorCompare(NSDictionary *a, NSDictionary *b, void *context) {
    (void)context;
    NSComparisonResult result = [a[@"identifier"] localizedCaseInsensitiveCompare:b[@"identifier"]];
    return result == NSOrderedSame ? [a[@"title"] compare:b[@"title"]] : result;
}

NSArray<NSDictionary *> *haoge_settingsshelf_inventoryDescriptors(NSString *preferencesDirectory,
    NSString *preferenceBundlesDirectory, NSString *systemPreferenceBundlesDirectory, BOOL *complete) {
    if (complete) *complete = NO;
    BOOL isDirectory = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:preferencesDirectory isDirectory:&isDirectory] || !isDirectory) return nil;

    __block BOOL enumerationFailed = NO;
    NSURL *rootURL = [NSURL fileURLWithPath:preferencesDirectory isDirectory:YES];
    NSDirectoryEnumerator *enumerator = [manager enumeratorAtURL:rootURL
        includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                           options:0
                      errorHandler:^BOOL(__unused NSURL *url, __unused NSError *error) {
        enumerationFailed = YES;
        return YES;
    }];
    if (!enumerator) return nil;

    NSMutableArray<NSDictionary *> *descriptors = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        if (![url.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
        if (!data) { enumerationFailed = YES; continue; }
        id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
        if (![plist isKindOfClass:NSDictionary.class]) { enumerationFailed = YES; continue; }
        NSDictionary *source = plist;
        id entryValue = source[@"entry"];
        if (!entryValue) continue;
        if (![entryValue isKindOfClass:NSDictionary.class]) { enumerationFailed = YES; continue; }
        NSDictionary *entry = entryValue;
        id outerFilter = source[@"filter"] ?: source[@"pl_filter"];
        if (!haoge_settingsshelf_inventoryFilterAllows(outerFilter) ||
            !haoge_settingsshelf_inventoryFilterAllows(entry[@"pl_filter"])) continue;

        NSString *bundle = [entry[@"bundle"] isKindOfClass:NSString.class] ? entry[@"bundle"] : nil;
        NSString *bundleName = [[bundle lastPathComponent] stringByDeletingPathExtension];
        NSString *explicitPath = [entry[@"bundlePath"] isKindOfClass:NSString.class] ? entry[@"bundlePath"] : nil;
        NSString *title = url.lastPathComponent.stringByDeletingPathExtension;
        // Never surface SettingsShelf's own PreferenceBundle as a plugin.
        if ([bundleName isEqualToString:@"HaogeSettingsShelfPrefs"] ||
            [explicitPath.lastPathComponent isEqualToString:@"HaogeSettingsShelfPrefs.bundle"]) continue;
        NSString *bundlePath = haoge_settingsshelf_resolvedBundlePath(entry, preferenceBundlesDirectory, systemPreferenceBundlesDirectory);
        if (!bundlePath) continue;
        NSString *label = [entry[@"label"] isKindOfClass:NSString.class] ? entry[@"label"] : nil;
        NSString *identifier = label.length ? label : title;
        if (!identifier.length || !title.length) continue;
        [descriptors addObject:@{@"identifier":identifier, @"title":title,
            @"name":label.length ? label : title, @"entry":entry, @"bundlePath":bundlePath}];
    }
    if (enumerationFailed) return nil;
    [descriptors sortUsingFunction:haoge_settingsshelf_descriptorCompare context:NULL];
    if (complete) *complete = YES;
    return [descriptors copy];
}

static NSString *haoge_settingsshelf_rowIdentifier(id row) {
    id value = [row respondsToSelector:@selector(identifier)] ? [row valueForKey:@"identifier"] :
        ([row isKindOfClass:NSDictionary.class] ? row[@"identifier"] : nil);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static NSString *haoge_settingsshelf_rowName(id row) {
    id value = [row respondsToSelector:@selector(name)] ? [row valueForKey:@"name"] :
        ([row isKindOfClass:NSDictionary.class] ? row[@"name"] : nil);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
NSArray *haoge_settingsshelf_inventoryBuildRows(NSArray<NSDictionary *> *descriptors,
    HaogeSettingsShelfInventoryRowGenerator generator, BOOL *complete) {
    if (complete) *complete = NO;
    if (![descriptors isKindOfClass:NSArray.class] || !generator) return nil;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    for (NSDictionary *descriptor in descriptors) {
        if (![descriptor isKindOfClass:NSDictionary.class]) return nil;
        BOOL generated = NO;
        NSArray *batch = generator(descriptor, &generated);
        if (!generated || ![batch isKindOfClass:NSArray.class]) return nil;
        for (id row in batch) {
            if (!row || row == NSNull.null) continue;
            NSString *identifier = haoge_settingsshelf_rowIdentifier(row);
            if (identifier.length) {
                if ([identifiers containsObject:identifier]) continue;
                [identifiers addObject:identifier];
            }
            [rows addObject:row];
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(id a, id b) {
        return [haoge_settingsshelf_rowName(a) localizedCaseInsensitiveCompare:haoge_settingsshelf_rowName(b)];
    }];
    if (complete) *complete = YES;
    return [rows copy];
}
NSArray *haoge_settingsshelf_inventoryRowsForOwner(NSArray *rows, id owner, id requester) {
    return owner && owner == requester && [rows isKindOfClass:NSArray.class] ? rows : @[];
}
BOOL haoge_settingsshelf_inventoryCommitRows(NSArray *__strong *lastKnownGood, NSArray *candidate, BOOL complete) {
    if (!lastKnownGood || !complete || ![candidate isKindOfClass:NSArray.class]) return NO;
    *lastKnownGood = [candidate copy];
    return YES;
}
