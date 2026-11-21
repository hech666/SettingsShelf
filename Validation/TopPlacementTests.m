// Foundation-only production regression executable. Run from the repository root:
// clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation -ISources
// Compile Sources/HaogeSettingsShelfGrouping.m and Validation/TopPlacementTests.m
// together, with -o /tmp/SettingsShelfTopPlacementTests.
// /tmp/SettingsShelfTopPlacementTests
#import <Foundation/Foundation.h>
#import "HaogeSettingsShelfGrouping.h"
#include <stdint.h>

static NSUInteger assertions;
static NSUInteger cases;
static NSString *context = @"startup";

static void Check(BOOL condition, const char *expression, int line) {
    ++assertions;
    if (!condition) {
        [NSException raise:@"TopPlacementFailure"
                    format:@"%@, line %d: %s", context, line, expression];
    }
}
#define CHECK(...) Check((__VA_ARGS__), #__VA_ARGS__, __LINE__)

@interface FakeEntry : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) NSInteger cellType;
@property(nonatomic, copy) NSDictionary<NSString *, id> *values;
- (id)propertyForKey:(NSString *)key;
@end
@implementation FakeEntry
- (id)propertyForKey:(NSString *)key { return self.values[key]; }
@end

static FakeEntry *Entry(NSString *identifier, NSInteger type, NSDictionary *values) {
    FakeEntry *entry = [FakeEntry new];
    entry.identifier = identifier;
    entry.cellType = type;
    entry.values = values;
    return entry;
}
static FakeEntry *Group(NSString *identifier) { return Entry(identifier, 0, @{}); }
static FakeEntry *System(NSString *identifier) {
    return Entry(identifier, 1, @{@"lazy-bundle": @"/System/Library/PreferenceBundles/System.bundle"});
}
static FakeEntry *Tweak(NSString *identifier) {
    return Entry(identifier, 1, @{@"lazy-bundle": @"/var/jb/Library/PreferenceBundles/ThirdParty.bundle",
                                  @"target": [NSObject new]});
}
static FakeEntry *App(NSString *identifier) {
    return Entry(identifier, 1, @{@"AppBundleID": @"org.example.thirdparty",
                                  @"target": [NSObject new]});
}
static NSArray *Navigation(void) {
    return @[Group(@"com.haoge.settingsshelf.category.group"),
             Entry(@"com.haoge.settingsshelf.category.tweaks", 1, @{}),
             Entry(@"com.haoge.settingsshelf.category.apps", 1, @{})];
}
static NSArray *Join(NSArray *left, NSArray *right) {
    return [left arrayByAddingObjectsFromArray:right];
}
static void SameObjects(NSArray *actual, NSArray *expected) {
    CHECK(actual.count == expected.count);
    for (NSUInteger i = 0; i < expected.count; ++i) CHECK(actual[i] == expected[i]);
}
static NSArray *Targets(NSArray *entries) {
    NSMutableArray *targets = [NSMutableArray array];
    for (FakeEntry *entry in entries) {
        id target = [entry propertyForKey:@"target"];
        CHECK(target != nil);
        [targets addObject:target];
    }
    return targets;
}
static void Bucket(NSArray *actual, NSArray *entries, NSArray *targets) {
    SameObjects(actual, entries);
    CHECK(entries.count == targets.count);
    for (NSUInteger i = 0; i < entries.count; ++i) {
        CHECK([actual[i] propertyForKey:@"target"] == targets[i]);
    }
}

@interface FakeRoot : NSObject
@property(nonatomic, strong) NSMutableArray *rows;
@property(nonatomic, copy) NSArray *navigation;
@property(nonatomic) NSUInteger expectedRemovalIndex;
@property(nonatomic) NSUInteger expectedInsertionIndex;
@property(nonatomic) NSUInteger deleteCalls;
@property(nonatomic) NSUInteger insertCalls;
- (instancetype)initWithRows:(NSArray *)rows navigation:(NSArray *)navigation;
- (NSArray *)specifiers;
- (void)removeContiguousSpecifiers:(NSArray *)specifiers animated:(BOOL)animated;
- (void)insertContiguousSpecifiers:(NSArray *)specifiers atIndex:(NSUInteger)index animated:(BOOL)animated;
@end
@implementation FakeRoot
- (instancetype)initWithRows:(NSArray *)rows navigation:(NSArray *)navigation {
    if ((self = [super init])) {
        _rows = [rows mutableCopy];
        _navigation = [navigation copy];
        _expectedRemovalIndex = NSNotFound;
        _expectedInsertionIndex = NSNotFound;
    }
    return self;
}
- (NSArray *)specifiers { return [self.rows copy]; }
- (void)removeContiguousSpecifiers:(NSArray *)specifiers animated:(BOOL)animated {
    NSUInteger index = self.expectedRemovalIndex;
    CHECK(!animated && specifiers.count > 0 && index != NSNotFound);
    CHECK(index <= self.rows.count && specifiers.count <= self.rows.count - index);
    // The harness arms the ORIGINAL snapshot index before each reverse-order
    // call. Never find by identifier (or ambiguously find the first repeated
    // navigation pointer). Check every object AND its immediate neighbours.
    for (NSUInteger i = 0; i < specifiers.count; ++i) {
        CHECK(self.rows[index + i] == specifiers[i]);
    }
    [self.rows removeObjectsInRange:NSMakeRange(index, specifiers.count)];
    self.expectedRemovalIndex = NSNotFound;
    ++self.deleteCalls;
}
- (void)insertContiguousSpecifiers:(NSArray *)specifiers atIndex:(NSUInteger)index animated:(BOOL)animated {
    CHECK(!animated && index == self.expectedInsertionIndex && index != NSNotFound);
    SameObjects(specifiers, self.navigation);
    [self.rows insertObjects:specifiers
                  atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, specifiers.count)]];
    self.expectedInsertionIndex = NSNotFound;
    ++self.insertCalls;
}
@end

static NSUInteger NavigationIndex(NSArray *rows, NSArray *navigation) {
    CHECK(navigation.count == 3);
    NSUInteger found = NSNotFound;
    for (NSUInteger i = 0; i + navigation.count <= rows.count; ++i) {
        BOOL matches = YES;
        for (NSUInteger j = 0; j < navigation.count; ++j) {
            if (rows[i + j] != navigation[j]) { matches = NO; break; }
        }
        if (matches) { CHECK(found == NSNotFound); found = i; }
    }
    CHECK(found != NSNotFound);
    return found;
}

// This is the production root transaction, not an alternate grouping/removal
// algorithm. The expected fixture supplies the insertion location; the real
// helper supplies the index used by the actual fake-root transaction.
static NSArray<NSValue *> *Reconcile(FakeRoot *root, HaogeSettingsShelfGroupingState *state,
                                    NSArray *navigation, NSArray *expected, BOOL expectInsertion) {
    NSArray *current = [root specifiers];
    NSArray *desired = [state haoge_settingsshelf_transform:current enabled:YES navigation:navigation];
    BOOL insertNavigation = NO;
    NSArray<NSValue *> *ranges = haoge_settingsshelf_rootRemovalRanges(current, desired, navigation,
                                                                     &insertNavigation);
    CHECK(insertNavigation == expectInsertion);
    NSUInteger previousEnd = 0;
    BOOL first = YES;
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        CHECK(range.length > 0 && range.location <= current.count &&
              range.length <= current.count - range.location);
        CHECK(first || previousEnd < range.location); // ascending, disjoint, maximal runs
        previousEnd = NSMaxRange(range);
        first = NO;
    }
    NSUInteger beforeDelete = root.deleteCalls, beforeInsert = root.insertCalls;
    for (NSValue *value in ranges.reverseObjectEnumerator) {
        NSRange range = value.rangeValue;
        root.expectedRemovalIndex = range.location;
        [root removeContiguousSpecifiers:[current subarrayWithRange:range] animated:NO];
    }
    if (insertNavigation) {
        NSArray *remainingRows = [root specifiers];
        NSUInteger insertionIndex = haoge_settingsshelf_navigationInsertionIndex(remainingRows);
        CHECK(insertionIndex == NavigationIndex(expected, navigation));
        root.expectedInsertionIndex = insertionIndex;
        [root insertContiguousSpecifiers:navigation atIndex:insertionIndex animated:NO];
    }
    CHECK(root.expectedRemovalIndex == NSNotFound);
    CHECK(root.deleteCalls - beforeDelete == ranges.count);
    CHECK(root.insertCalls - beforeInsert == (expectInsertion ? 1U : 0U));
    SameObjects([root specifiers], expected);
    return ranges;
}

static void Fresh(NSString *name, NSArray *current, NSArray *navigation, NSArray *expected,
                  NSArray *tweaks, NSArray *apps, BOOL expectInsertion) {
    context = name;
    ++cases;
    NSArray *tweakTargets = Targets(tweaks), *appTargets = Targets(apps);
    HaogeSettingsShelfGroupingState *state = [HaogeSettingsShelfGroupingState new];
    // Also verify the cold (pre-table-load) construction path directly.
    SameObjects([state haoge_settingsshelf_transform:current enabled:YES navigation:navigation], expected);
    FakeRoot *root = [[FakeRoot alloc] initWithRows:current navigation:navigation];
    Reconcile(root, state, navigation, expected, expectInsertion);
    Bucket(state.haoge_settingsshelf_tweaks, tweaks, tweakTargets);
    Bucket(state.haoge_settingsshelf_apps, apps, appTargets);
}

static void Permute(NSMutableArray *items, NSUInteger index, void (^visit)(NSArray *)) {
    if (index == items.count) { visit([items copy]); return; }
    for (NSUInteger i = index; i < items.count; ++i) {
        [items exchangeObjectAtIndex:index withObjectAtIndex:i];
        Permute(items, index + 1, visit);
        [items exchangeObjectAtIndex:index withObjectAtIndex:i];
    }
}
static uint32_t NextRandom(uint32_t *seed) {
    *seed = *seed * UINT32_C(1664525) + UINT32_C(1013904223);
    return *seed;
}
// External host/plugin insertion: intentionally bypass the mutation counters.
static void HostInsert(FakeRoot *root, NSArray *rows, NSUInteger index) {
    [root.rows insertObjects:rows
                  atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, rows.count)]];
}

static void PlacementCases(void) {
    NSArray *nav = Navigation();
    FakeEntry *systemGroup = Group(@"WIRELESS_GROUP"), *wifi = System(@"WIFI");
    FakeEntry *secondGroup = Group(@"SECURITY_GROUP"), *password = System(@"PASSWORD");
    FakeEntry *tweakGroup = Group(@"TWEAK_GROUP"), *appGroup = Group(@"APP_GROUP");
    FakeEntry *tweak = Tweak(@"original-tweak"), *app = App(@"original-app");
    NSArray *system = @[systemGroup, wifi, secondGroup, password];
    NSArray *raw = @[systemGroup, wifi, tweakGroup, tweak, appGroup, app, secondGroup, password];
    NSArray *expected = Join(nav, system);
    Fresh(@"empty cold construction", @[], nav, nav, @[], @[], YES);
    Fresh(@"cold mixed groups", raw, nav, expected, @[tweak], @[app], YES);
    Fresh(@"legacy bottom navigation", Join(raw, nav), nav, expected, @[tweak], @[app], YES);
    Fresh(@"already top with late third-party rows", Join(nav, raw), nav, expected, @[tweak], @[app], NO);
    Fresh(@"all third-party groups disappear", @[tweakGroup, tweak, appGroup, app], nav,
          nav, @[tweak], @[app], YES);

    // Every subset, including no navigation and all navigation stranded below
    // the first system group. Existing identifiers must not suppress insertion.
    for (NSUInteger mask = 0; mask < 8; ++mask) {
        NSMutableArray *current = [NSMutableArray arrayWithObject:systemGroup];
        for (NSUInteger i = 0; i < nav.count; ++i) if (mask & (1U << i)) [current addObject:nav[i]];
        [current addObjectsFromArray:@[wifi, tweakGroup, tweak, appGroup, app, secondGroup, password]];
        Fresh([NSString stringWithFormat:@"partial navigation mask %lu", (unsigned long)mask],
              current, nav, expected, @[tweak], @[app], YES);
    }
    __block NSUInteger order = 0;
    Permute([nav mutableCopy], 0, ^(NSArray *permutation) {
        BOOL correct = permutation[0] == nav[0] && permutation[1] == nav[1] && permutation[2] == nav[2];
        Fresh([NSString stringWithFormat:@"navigation permutation %lu", (unsigned long)order++],
              Join(permutation, raw), nav, expected, @[tweak], @[app], !correct);
    });
    CHECK(order == 6);

    NSArray *stale = Navigation(); // same identifiers, different objects
    Fresh(@"same-ID stale top objects", Join(stale, raw), nav, expected, @[tweak], @[app], YES);
    Fresh(@"duplicate canonical and same-ID navigation",
          Join(nav, @[systemGroup, nav[0], wifi, stale[1], nav[2], tweakGroup, tweak,
                      appGroup, app, secondGroup, password, stale[2], nav[1]]),
          nav, expected, @[tweak], @[app], NO);
    Fresh(@"broken duplicate navigation requires one replacement",
          @[nav[2], systemGroup, nav[0], wifi, nav[0], nav[1], tweakGroup, tweak,
            appGroup, app, secondGroup, nav[2], password],
          nav, expected, @[tweak], @[app], YES);
    Fresh(@"system rows split all navigation entries",
          @[nav[0], systemGroup, nav[1], wifi, nav[2], secondGroup, password, tweakGroup, tweak, appGroup, app],
          nav, expected, @[tweak], @[app], YES);

    // Mixed system/third-party sections retain their system anchor and exact
    // object order; trailing empty system groups are not arbitrarily removed.
    FakeEntry *apple = Entry(@"APPLE_APP", 1, @{@"AppBundleID": @"com.apple.Preferences"});
    FakeEntry *empty = Group(@"EMPTY_SYSTEM_GROUP");
    Fresh(@"mixed system groups and Apple app stay in original order",
          @[systemGroup, tweak, wifi, secondGroup, app, apple, password, empty], nav,
          Join(nav, @[systemGroup, wifi, secondGroup, apple, password, empty]), @[tweak], @[app], YES);

    // Pin down range boundaries, not just the resulting list. System rows
    // separate three deletions and make forward-order application invalid.
    context = @"original-index ascending ranges and reverse deletions";
    ++cases;
    HaogeSettingsShelfGroupingState *state = [HaogeSettingsShelfGroupingState new];
    FakeRoot *root = [[FakeRoot alloc] initWithRows:@[nav[0], nav[1], nav[2], tweakGroup,
                                                    tweak, systemGroup, wifi, appGroup, app,
                                                    secondGroup, password, stale[0], stale[1], stale[2]]
                                       navigation:nav];
    NSArray<NSValue *> *ranges = Reconcile(root, state, nav, expected, NO);
    CHECK(ranges.count == 3);
    CHECK(NSEqualRanges(ranges[0].rangeValue, NSMakeRange(3, 2)));
    CHECK(NSEqualRanges(ranges[1].rangeValue, NSMakeRange(7, 2)));
    CHECK(NSEqualRanges(ranges[2].rangeValue, NSMakeRange(11, 3)));
    // The optional result pointer must really be optional.
    CHECK(haoge_settingsshelf_rootRemovalRanges(root.specifiers, expected, nav, NULL).count == 0);
}

static void PermutationCases(void) {
    NSArray *nav = Navigation();
    FakeEntry *system = System(@"PERMUTATION_SYSTEM"), *app = App(@"PERMUTATION_APP");
    __block NSUInteger visited = 0;
    // Exhaust all 5! interleavings of the three canonical navigation objects,
    // a system row, and a third-party row. Expected rows are an explicit fixture.
    Permute([@[nav[0], nav[1], nav[2], system, app] mutableCopy], 0, ^(NSArray *current) {
        BOOL top = current[0] == nav[0] && current[1] == nav[1] && current[2] == nav[2];
        Fresh([NSString stringWithFormat:@"exhaustive five-row permutation %lu", (unsigned long)visited++],
              current, nav, Join(nav, @[system]), @[], @[app], !top);
    });
    CHECK(visited == 120);

    uint32_t seed = UINT32_C(0x5348454c);
    for (NSUInteger trial = 0; trial < 24; ++trial) {
        FakeEntry *wifi = System(@"SHUFFLED_WIFI"), *password = System(@"SHUFFLED_PASSWORD");
        FakeEntry *tweak = Tweak(@"SHUFFLED_TWEAK"), *otherApp = App(@"SHUFFLED_APP");
        NSMutableArray *current = [@[nav[0], nav[1], nav[2], wifi, password, tweak, otherApp] mutableCopy];
        if (trial % 2 == 0) [current addObjectsFromArray:nav]; // repeated identical pointers
        if (trial % 3 == 0) [current addObjectsFromArray:Navigation()]; // repeated identifiers only
        for (NSUInteger remaining = current.count; remaining > 1; --remaining) {
            NSUInteger index = (NSUInteger)NextRandom(&seed) % remaining;
            [current exchangeObjectAtIndex:remaining - 1 withObjectAtIndex:index];
        }
        // An explicit whitelist oracle for system order, not a second
        // implementation of grouping, category detection, or removal ranges.
        NSArray *systemOrder = [current indexOfObjectIdenticalTo:wifi] < [current indexOfObjectIdenticalTo:password]
            ? @[wifi, password] : @[password, wifi];
        BOOL top = current[0] == nav[0] && current[1] == nav[1] && current[2] == nav[2];
        Fresh([NSString stringWithFormat:@"deterministic mixed shuffle %lu", (unsigned long)trial],
              current, nav, Join(nav, systemOrder), @[tweak], @[otherApp], !top);
    }
}

static void ContinuousUpdateCases(void) {
    context = @"continuous late multi-group app/tweak insertion";
    ++cases;
    NSArray *nav = Navigation();
    FakeEntry *systemGroup = Group(@"LIVE_SYSTEM_GROUP"), *wifi = System(@"WIFI");
    FakeEntry *secondGroup = Group(@"LIVE_SECURITY_GROUP"), *password = System(@"LIVE_PASSWORD");
    FakeEntry *firstTweak = Tweak(@"LIVE_ORIGINAL_TWEAK"), *firstApp = App(@"LIVE_ORIGINAL_APP");
    NSArray *system = @[systemGroup, wifi, secondGroup, password];
    NSArray *expected = Join(nav, system);
    NSMutableArray *tweaks = [NSMutableArray arrayWithObject:firstTweak];
    NSMutableArray *apps = [NSMutableArray arrayWithObject:firstApp];
    NSMutableArray *tweakTargets = [Targets(tweaks) mutableCopy];
    NSMutableArray *appTargets = [Targets(apps) mutableCopy];
    NSArray *initial = @[systemGroup, wifi, Group(@"LIVE_TWEAK_GROUP"), firstTweak,
                         Group(@"LIVE_APP_GROUP"), firstApp, secondGroup, password];
    HaogeSettingsShelfGroupingState *state = [HaogeSettingsShelfGroupingState new];
    FakeRoot *root = [[FakeRoot alloc] initWithRows:initial navigation:nav];
    Reconcile(root, state, nav, expected, YES);
    for (NSUInteger round = 0; round < 6; ++round) {
        context = [NSString stringWithFormat:@"continuous three-group insertion round %lu", (unsigned long)round];
        FakeEntry *tweak = Tweak([NSString stringWithFormat:@"late-tweak-%lu", (unsigned long)round]);
        FakeEntry *app = App([NSString stringWithFormat:@"late-app-%lu", (unsigned long)round]);
        FakeEntry *mixedTweak = Tweak([NSString stringWithFormat:@"mixed-tweak-%lu", (unsigned long)round]);
        FakeEntry *mixedApp = App([NSString stringWithFormat:@"mixed-app-%lu", (unsigned long)round]);
        // Three independent external insertions: ahead of/in the navigation,
        // among existing system sections, and at the tail. No rebuild of state.
        HostInsert(root, @[Group([NSString stringWithFormat:@"late-tweak-group-%lu", (unsigned long)round]), tweak],
                   round == 0 ? 0 : 1);
        HostInsert(root, @[Group([NSString stringWithFormat:@"late-app-group-%lu", (unsigned long)round]), app],
                   root.rows.count - 1);
        HostInsert(root, @[Group([NSString stringWithFormat:@"late-mixed-group-%lu", (unsigned long)round]),
                           mixedTweak, mixedApp], root.rows.count);
        [tweaks addObjectsFromArray:@[tweak, mixedTweak]];
        [apps addObjectsFromArray:@[app, mixedApp]];
        [tweakTargets addObjectsFromArray:Targets(@[tweak, mixedTweak])];
        [appTargets addObjectsFromArray:Targets(@[app, mixedApp])];
        // Prefix-only removals preserve an already contiguous canonical run;
        // insertions inside the run require removing and reinserting it.
        Reconcile(root, state, nav, expected, round != 0);
        Bucket(state.haoge_settingsshelf_tweaks, tweaks, tweakTargets);
        Bucket(state.haoge_settingsshelf_apps, apps, appTargets);
        for (NSUInteger repeat = 0; repeat < 3; ++repeat) {
            CHECK(Reconcile(root, state, nav, expected, NO).count == 0);
        }
    }
    CHECK(tweaks.count == 13 && apps.count == 13);
    Bucket(state.haoge_settingsshelf_tweaks, tweaks, tweakTargets);
    Bucket(state.haoge_settingsshelf_apps, apps, appTargets);

    // A later SYSTEM transaction splits the navigation. Preserve the host's
    // current order of system rows/groups rather than imposing historical raw
    // ordering. The production root API removes/inserts; it does not rebuild.
    context = @"late system group splits navigation without system reorder";
    ++cases;
    FakeEntry *lateGroup = Group(@"LATE_HOST_SYSTEM_GROUP"), *lateSystem = System(@"LATE_HOST_SYSTEM");
    HostInsert(root, @[lateGroup, lateSystem], 2);
    // The delayed section is anchored immediately before the first network
    // group, after the newly inserted host section; system order stays intact.
    expected = Join(@[lateGroup, lateSystem], Join(nav, system));
    Reconcile(root, state, nav, expected, YES);
    Bucket(state.haoge_settingsshelf_tweaks, tweaks, tweakTargets);
    Bucket(state.haoge_settingsshelf_apps, apps, appTargets);
    NSArray *raw = [state.haoge_settingsshelf_raw copy];
    NSUInteger beforeDelete = root.deleteCalls, beforeInsert = root.insertCalls;
    for (NSUInteger repeat = 0; repeat < 32; ++repeat) {
        CHECK(Reconcile(root, state, nav, expected, NO).count == 0);
    }
    CHECK(root.deleteCalls == beforeDelete && root.insertCalls == beforeInsert);
    SameObjects(state.haoge_settingsshelf_raw, raw);
    Bucket(state.haoge_settingsshelf_tweaks, tweaks, tweakTargets);
    Bucket(state.haoge_settingsshelf_apps, apps, appTargets);
}

static void StrictFakeCases(void) {
    context = @"fake rejects noncontiguous or identifier-only deletion";
    ++cases;
    NSArray *nav = Navigation();
    FakeEntry *a = System(@"a"), *b = System(@"b"), *c = System(@"c");
    FakeRoot *root = [[FakeRoot alloc] initWithRows:@[a, b, c] navigation:nav];
    for (NSArray *invalid in @[@[a, c], @[System(@"a"), b]]) {
        BOOL rejected = NO;
        root.expectedRemovalIndex = 0;
        @try {
            [root removeContiguousSpecifiers:invalid animated:NO];
        } @catch (NSException *exception) {
            CHECK([exception.name isEqualToString:@"TopPlacementFailure"]);
            rejected = YES;
        }
        CHECK(rejected);
        SameObjects(root.specifiers, @[a, b, c]);
        CHECK(root.deleteCalls == 0);
        root.expectedRemovalIndex = NSNotFound;
    }
}

int main(void) {
    @autoreleasepool {
        @try {
            StrictFakeCases();
            PlacementCases();
            PermutationCases();
            ContinuousUpdateCases();
            NSLog(@"SettingsShelf top placement: %lu cases, %lu assertions passed",
                  (unsigned long)cases, (unsigned long)assertions);
            return 0;
        } @catch (NSException *exception) {
            NSLog(@"FAILED [%@]: %@: %@", context, exception.name, exception.reason);
            return 1;
        }
    }
}
