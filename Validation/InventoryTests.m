#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "HaogeSettingsShelfInventory.h"

static NSUInteger assertions;
#define CHECK(x) do { ++assertions; if (!(x)) { NSLog(@"FAILED line %d: %s", __LINE__, #x); return 1; } } while (0)
static BOOL writePlist(NSDictionary *plist, NSString *path) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:path atomically:YES];
}
int main(void) { @autoreleasepool {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSString *prefs = [base stringByAppendingPathComponent:@"Library/PreferenceLoader/Preferences"];
    NSString *bundles = [base stringByAppendingPathComponent:@"Library/PreferenceBundles"];
    NSString *system = [base stringByAppendingPathComponent:@"System/Library/PreferenceBundles"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:[prefs stringByAppendingPathComponent:@"Nested"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[bundles stringByAppendingPathComponent:@"Kayoko.bundle"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[system stringByAppendingPathComponent:@"ControlCenter18.bundle"] withIntermediateDirectories:YES attributes:nil error:nil];
    double cf = kCFCoreFoundationVersionNumber;
    NSDictionary *kayoko = @{@"entry":@{@"label":@"Kayoko", @"bundle":@"Kayoko", @"pl_filter":@{@"CoreFoundationVersion":@[@(cf-1.0)]}}};
    NSDictionary *cc = @{@"filter":@{@"CoreFoundationVersion":@[@(cf-1.0),@(cf+1.0)]}, @"entry":@{@"label":@"ControlCenter18", @"bundle":@"ControlCenter18"}};
    NSDictionary *future = @{@"entry":@{@"label":@"Future", @"bundle":@"Kayoko", @"pl_filter":@{@"CoreFoundationVersion":@[@(cf+1.0)]}}};
    NSDictionary *upperExclusive = @{@"entry":@{@"label":@"UpperBound", @"bundle":@"Kayoko", @"pl_filter":@{@"CoreFoundationVersion":@[@(cf-1.0),@(cf)]}}};
    NSDictionary *missingBundle = @{@"entry":@{@"label":@"Removed", @"bundle":@"RemovedBundle"}};
    CHECK(writePlist(kayoko,[prefs stringByAppendingPathComponent:@"Nested/Kayoko.plist"]));
    CHECK(writePlist(cc,[prefs stringByAppendingPathComponent:@"ControlCenter18.plist"]));
    CHECK(writePlist(future,[prefs stringByAppendingPathComponent:@"Future.plist"]));
    CHECK(writePlist(upperExclusive,[prefs stringByAppendingPathComponent:@"UpperBound.plist"]));
    CHECK(writePlist(missingBundle,[prefs stringByAppendingPathComponent:@"Removed.plist"]));
    BOOL complete = NO;
    NSArray *inventory = haoge_settingsshelf_inventoryDescriptors(prefs,bundles,system,&complete);
    CHECK(complete && inventory.count==2);
    CHECK([inventory[0][@"identifier"] isEqualToString:@"ControlCenter18"]);
    CHECK([inventory[1][@"identifier"] isEqualToString:@"Kayoko"]);
    CHECK([inventory[1][@"title"] isEqualToString:@"Kayoko"]);
    CHECK([inventory[0][@"bundlePath"] isEqualToString:[system stringByAppendingPathComponent:@"ControlCenter18.bundle"]]);
    // Explicit paths take priority; an invalid explicit path falls back to bundle roots.
    NSString *explicitBundle = [base stringByAppendingPathComponent:@"Explicit.bundle"];
    CHECK([fm createDirectoryAtPath:explicitBundle withIntermediateDirectories:YES attributes:nil error:nil]);
    CHECK(writePlist(@{@"entry":@{@"label":@"Explicit", @"bundle":@"Kayoko", @"bundlePath":explicitBundle,
        @"cellClass":@"ExistingVendorCell"}}, [prefs stringByAppendingPathComponent:@"Explicit.plist"]));
    CHECK(writePlist(@{@"entry":@{@"bundle":@"Kayoko", @"bundlePath":@"/missing/bundle"}},
        [prefs stringByAppendingPathComponent:@"FilenameFallback.plist"]));
    CHECK(writePlist(@{@"entry":@{@"label":@"Self", @"bundle":@"HaogeSettingsShelfPrefs"}},
        [prefs stringByAppendingPathComponent:@"Own.plist"]));
    CHECK(writePlist(@{@"entry":@{@"label":@"SelfPath", @"bundlePath":[base stringByAppendingPathComponent:@"HaogeSettingsShelfPrefs.bundle"]}},
        [prefs stringByAppendingPathComponent:@"OwnPath.plist"]));
    CHECK(writePlist(@{@"pl_filter":@{@"CoreFoundationVersion":@[@(cf+1.0)]}, @"entry":@{@"label":@"OuterFuture", @"bundle":@"Kayoko"}},
        [prefs stringByAppendingPathComponent:@"OuterFuture.plist"]));
    CHECK(writePlist(@{@"filter":@{}, @"pl_filter":@{@"CoreFoundationVersion":@[@(cf+1.0)]},
        @"entry":@{@"label":@"FilterPriority", @"bundle":@"Kayoko"}}, [prefs stringByAppendingPathComponent:@"Priority.plist"]));
    inventory = haoge_settingsshelf_inventoryDescriptors(prefs,bundles,system,&complete);
    CHECK(complete && inventory.count == 5);
    CHECK([inventory[1][@"bundlePath"] isEqualToString:explicitBundle]);
    CHECK([inventory[1][@"entry"][@"cellClass"] isEqualToString:@"ExistingVendorCell"]);
    CHECK([inventory[2][@"identifier"] isEqualToString:@"FilenameFallback"]);
    CHECK([inventory[2][@"bundlePath"] isEqualToString:[bundles stringByAppendingPathComponent:@"Kayoko.bundle"]]);

    // Cold start has no root observations at all; every descriptor still generates a row.
    __block NSUInteger generatedCount = 0;
    HaogeSettingsShelfInventoryRowGenerator generate = ^NSArray *(NSDictionary *descriptor, BOOL *success) {
        ++generatedCount;
        *success = YES;
        return @[@{@"identifier":descriptor[@"identifier"], @"name":descriptor[@"title"],
            @"target":@"actual-category", @"lazy-bundle":descriptor[@"bundlePath"]}];
    };
    NSArray *__strong lastGood = nil;
    NSArray *candidate = haoge_settingsshelf_inventoryBuildRows(inventory, generate, &complete);
    CHECK(complete && candidate.count == 5 && generatedCount == 5);
    CHECK(haoge_settingsshelf_inventoryCommitRows(&lastGood, candidate, complete));
    CHECK(lastGood.count == 5);
    // Root-only partial refreshes cannot replace this descriptor-driven inventory.
    NSArray *partialRoot = @[lastGood[0]];
    CHECK(partialRoot.count == 1 && lastGood.count == 5);
    for (NSUInteger i = 0; i < 25; ++i) {
        NSArray *reentered = haoge_settingsshelf_inventoryDescriptors(prefs,bundles,system,&complete);
        CHECK(complete && [reentered isEqualToArray:inventory]);
        candidate = haoge_settingsshelf_inventoryBuildRows(reentered, generate, &complete);
        CHECK(complete && candidate.count == 5 && [candidate isEqualToArray:lastGood]);
    }
    // Duplicate IDs are emitted once; final order is by generated name, not discovery order.
    NSArray *duplicates = @[@{@"identifier":@"z", @"title":@"zebra", @"bundlePath":explicitBundle},
        @{@"identifier":@"a", @"title":@"Alpha", @"bundlePath":explicitBundle},
        @{@"identifier":@"z", @"title":@"duplicate", @"bundlePath":explicitBundle}];
    candidate = haoge_settingsshelf_inventoryBuildRows(duplicates, generate, &complete);
    CHECK(complete && candidate.count == 2);
    CHECK([candidate[0][@"name"] isEqualToString:@"Alpha"]);
    CHECK([candidate[1][@"name"] isEqualToString:@"zebra"]);
    candidate = haoge_settingsshelf_inventoryBuildRows(inventory,
        ^NSArray *(__unused NSDictionary *descriptor, BOOL *success) { *success = NO; return nil; }, &complete);
    CHECK(!complete && !candidate);
    CHECK(!haoge_settingsshelf_inventoryCommitRows(&lastGood,candidate,complete));
    CHECK(lastGood.count == 5);

    // Failed generation may reuse rows only for the same live controller.
    NSObject *owner = [NSObject new];
    NSObject *otherOwner = [NSObject new];
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, owner, owner) == lastGood);
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, owner, otherOwner).count == 0);
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, nil, otherOwner).count == 0);
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, owner, nil).count == 0);
    __weak NSObject *weakOwner;
    @autoreleasepool {
        NSObject *temporaryOwner = [NSObject new];
        weakOwner = temporaryOwner;
        CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, weakOwner, temporaryOwner) == lastGood);
    }
    CHECK(weakOwner == nil); // cache helper must not retain controller or create a cycle
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, weakOwner, otherOwner).count == 0);
    CHECK(haoge_settingsshelf_inventoryRowsForOwner(lastGood, weakOwner, weakOwner).count == 0);

    NSString *bad = [prefs stringByAppendingPathComponent:@"Nested/Broken.plist"];
    CHECK([[NSData dataWithBytes:"not a plist" length:11] writeToFile:bad atomically:YES]);
    complete = YES;
    CHECK(haoge_settingsshelf_inventoryDescriptors(prefs,bundles,system,&complete)==nil);
    CHECK(!complete); // incomplete scans cannot authorize cache pruning
    CHECK(!haoge_settingsshelf_inventoryCommitRows(&lastGood,nil,complete));
    CHECK(lastGood.count == 5);
    CHECK([fm removeItemAtPath:bad error:nil]);
    CHECK(writePlist(@{@"entry":@"not a dictionary"},bad));
    CHECK(haoge_settingsshelf_inventoryDescriptors(prefs,bundles,system,&complete) == nil && !complete);
    CHECK(!haoge_settingsshelf_inventoryCommitRows(&lastGood,nil,complete) && lastGood.count == 5);
    CHECK([fm removeItemAtPath:bad error:nil]);
    candidate = haoge_settingsshelf_inventoryBuildRows(@[],generate,&complete);
    CHECK(complete && candidate.count == 0);
    CHECK(haoge_settingsshelf_inventoryCommitRows(&lastGood,candidate,complete) && lastGood.count == 0);
    [fm removeItemAtPath:base error:nil];
    NSLog(@"SettingsShelf inventory: %lu assertions passed",(unsigned long)assertions);
    return 0;
} }
