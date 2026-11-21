// Foundation-only tests; also use the strict fake Preferences transaction.
#define main haoge_settingsshelf_legacyPlacementMain
#import "TopPlacementTests.m"
#undef main

int main(void) { @autoreleasepool { @try {
    NSArray *nav = Navigation();
    FakeEntry *ag = Group(@"APPLE_ACCOUNT_GROUP"), *account = System(@"APPLE_ACCOUNT");
    FakeEntry *ng = Group(@"WIRELESS_GROUP"), *air = System(@"AIRPLANE_MODE");
    FakeEntry *wifi = System(@"WIFI"), *bt = System(@"Bluetooth");
    FakeEntry *sg = Group(@"OTHER_GROUP"), *sound = System(@"SOUNDS");
    FakeEntry *tweak = Tweak(@"com.example.tweak"), *app = App(@"com.example.app");
    NSArray *prefix = @[ag, account], *network = @[ng, air, wifi, bt, sg, sound];
    NSArray *expected = Join(prefix, Join(nav, network));
    Fresh(@"account then navigation then complete network section", Join(prefix, network), nav, expected, @[], @[], YES);
    Fresh(@"move v6 top navigation below account", Join(nav, Join(prefix, network)), nav, expected, @[], @[], YES);
    Fresh(@"correct placement is stable", expected, nav, expected, @[], @[], NO);
    Fresh(@"third party rows do not offset original deletion ranges",
          Join(@[Group(@"TWEAK_GROUP"), tweak], Join(prefix, Join(nav, Join(network, @[Group(@"APP_GROUP"), app])))),
          nav, expected, @[tweak], @[app], NO);
    Fresh(@"same identifier stale navigation replaced", Join(prefix, Join(Navigation(), network)), nav, expected, @[], @[], YES);
    Fresh(@"canonical correct run retained while duplicate run deleted", Join(Navigation(), expected), nav, expected, @[], @[], NO);
    Fresh(@"wifi without account keeps entire network section", network, nav, Join(nav, network), @[], @[], YES);
    Fresh(@"account without network inserts at account section end", Join(prefix, @[sg, sound]), nav,
          Join(prefix, Join(nav, @[sg, sound])), @[], @[], YES);
    Fresh(@"account only inserts after avatar", prefix, nav, Join(prefix, nav), @[], @[], YES);
    Fresh(@"no recognizable anchors retains safe fallback", @[sg, sound], nav, Join(nav, @[sg, sound]), @[], @[], YES);
    Fresh(@"ungrouped network anchor does not precede Apple account", @[account, wifi, bt], nav,
          Join(@[account], Join(nav, @[wifi, bt])), @[], @[], YES);
    FakeEntry *own = Tweak(@"com.haoge.settingsshelf");
    Fresh(@"old self PreferenceLoader entry never appears", Join(prefix, Join(network, @[Group(@"SELF_GROUP"), own])),
          nav, expected, @[], @[], YES);
    context = @"explicit anchor indexes and system object identity";
    CHECK(haoge_settingsshelf_navigationInsertionIndex(Join(prefix, network)) == 2);
    CHECK(haoge_settingsshelf_navigationInsertionIndex(network) == 0);
    CHECK(haoge_settingsshelf_navigationInsertionIndex(prefix) == 2);
    CHECK(haoge_settingsshelf_navigationInsertionIndex(@[]) == 0);
    HaogeSettingsShelfGroupingState *state = [HaogeSettingsShelfGroupingState new];
    FakeRoot *root = [[FakeRoot alloc] initWithRows:Join(nav, network) navigation:nav];
    Reconcile(root, state, nav, Join(nav, network), NO);
    HostInsert(root, prefix, 0); // account arrives through a late host transaction
    SameObjects([state haoge_settingsshelf_transform:root.specifiers enabled:YES navigation:nav], expected);
    Reconcile(root, state, nav, expected, NO);
    for (NSUInteger round = 0; round < 12; ++round) {
        FakeEntry *late = Tweak([NSString stringWithFormat:@"late-%lu", (unsigned long)round]);
        HostInsert(root, @[Group(@"LATE_TWEAK_GROUP"), late], 3); // splits navigation
        Reconcile(root, state, nav, expected, YES);
        CHECK([state.haoge_settingsshelf_tweaks containsObject:late]);
        CHECK(state.haoge_settingsshelf_tweaks.lastObject == late);
        for (NSUInteger repeat = 0; repeat < 8; ++repeat) CHECK(Reconcile(root, state, nav, expected, NO).count == 0);
    }
    NSLog(@"SettingsShelf account placement: %lu fixtures, %lu assertions passed", (unsigned long)cases, (unsigned long)assertions);
    return 0;
} @catch (NSException *exception) {
    NSLog(@"FAILED [%@]: %@", context, exception.reason); return 1;
} } }
