#import "HaogeSettingsShelfRuntime.h"
#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfPaths.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <substrate.h>
#import <objc/runtime.h>

static char HaogeSettingsShelfStateKey;
static __weak PSListController *haoge_settingsshelf_root;
static Class haoge_settingsshelf_rootClass;
static NSArray *haoge_settingsshelf_navigation;
static NSUInteger haoge_settingsshelf_hits;
static __thread NSUInteger haoge_settingsshelf_busy;
static BOOL haoge_settingsshelf_reconcilePending;
static NSMutableSet *haoge_settingsshelf_installed;
static IMP haoge_settingsshelf_originalSpecifiers;

static BOOL haoge_settingsshelf_isRoot(id value) {
    return value && haoge_settingsshelf_rootClass && [value isKindOfClass:haoge_settingsshelf_rootClass];
}
static HaogeSettingsShelfGroupingState *haoge_settingsshelf_state(id root) {
    HaogeSettingsShelfGroupingState *state = objc_getAssociatedObject(root, &HaogeSettingsShelfStateKey);
    if (!state) {
        state = [HaogeSettingsShelfGroupingState new];
        objc_setAssociatedObject(root, &HaogeSettingsShelfStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static NSArray *haoge_settingsshelf_navigationRows(void) {
    if (haoge_settingsshelf_navigation.count == 3) return haoge_settingsshelf_navigation;
    Class detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    if (!detail) {
        NSString *path = haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle");
        NSBundle *bundle = [NSBundle bundleWithPath:path]; NSError *error = nil;
        if (![bundle isLoaded] && ![bundle loadAndReturnError:&error]) {
            NSLog(@"[SettingsShelf] preference bundle unavailable: %@", error.localizedDescription); return @[];
        }
        detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    }
    if (!detail) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"越狱插件和应用软件"];
    group.identifier = @"com.haoge.settingsshelf.category.group"; [rows addObject:group];
    for (NSString *category in @[@"tweaks", @"apps"]) {
        BOOL apps = [category isEqualToString:@"apps"];
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:apps ? @"应用软件" : @"越狱插件"
            target:nil set:nil get:nil detail:detail cell:PSLinkCell edit:nil];
        row.identifier = [@"com.haoge.settingsshelf.category." stringByAppendingString:category];
        [row setProperty:category forKey:@"HaogeSettingsShelfCategory"];
        NSString *file = apps ? @"HaogeSettingsShelfApps@2x.png" : @"HaogeSettingsShelfTweaks@2x.png";
        NSString *imagePath = [haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle") stringByAppendingPathComponent:file];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (image.CGImage) [row setProperty:[UIImage imageWithCGImage:image.CGImage scale:2 orientation:UIImageOrientationUp] forKey:@"iconImage"];
        [rows addObject:row];
    }
    haoge_settingsshelf_navigation = [rows copy]; return haoge_settingsshelf_navigation;
}

NSDictionary *haoge_settingsshelf_snapshot(void) {
    if (![NSThread isMainThread]) return @{};
    PSListController *root = haoge_settingsshelf_root;
    HaogeSettingsShelfGroupingState *state = root ? haoge_settingsshelf_state(root) : nil;
    return @{@"loaded":@YES, @"root":root ? NSStringFromClass(root.class) : @"", @"hits":@(haoge_settingsshelf_hits),
        @"tweaks":state.haoge_settingsshelf_tweaks ?: @[], @"apps":state.haoge_settingsshelf_apps ?: @[]};
}

static BOOL haoge_settingsshelf_containsIdentical(NSArray *array, id object) {
    for (id item in array) if (item == object) return YES;
    return NO;
}
static BOOL haoge_settingsshelf_containsIdentifier(NSArray *array, NSString *identifier) {
    if (!identifier.length) return NO;
    for (id item in array) if ([[item identifier] isEqualToString:identifier]) return YES;
    return NO;
}
// Match TweaksHub's deferred root insertion flow: let the system transaction
// finish, then remove each moved contiguous run through PSListController APIs.
static void haoge_settingsshelf_reconcile(PSListController *root) {
    if (!root || !haoge_settingsshelf_isRoot(root) || haoge_settingsshelf_busy || ![NSThread isMainThread]) return;
    ++haoge_settingsshelf_busy;
    @try {
        NSArray *current = [root specifiers];
        if (![current isKindOfClass:NSArray.class]) return;
        NSArray *navigation = haoge_settingsshelf_navigationRows();
        if (navigation.count != 3) return;
        NSArray *desired = [haoge_settingsshelf_state(root) haoge_settingsshelf_transform:current enabled:YES navigation:navigation];

        NSMutableArray<NSValue *> *ranges = [NSMutableArray array]; NSInteger start = -1;
        for (NSUInteger i = 0; i <= current.count; ++i) {
            BOOL remove = i < current.count && !haoge_settingsshelf_containsIdentical(desired, current[i]);
            if (remove && start < 0) start = (NSInteger)i;
            if (!remove && start >= 0) { [ranges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)start, i - (NSUInteger)start)]]; start = -1; }
        }
        for (NSValue *value in ranges.reverseObjectEnumerator) {
            NSArray *run = [current subarrayWithRange:value.rangeValue];
            if (run.count) [root removeContiguousSpecifiers:run animated:NO];
        }

        NSMutableArray *missingNavigation = [NSMutableArray array];
        for (id row in navigation) if (!haoge_settingsshelf_containsIdentifier(current, [row identifier])) [missingNavigation addObject:row];
        if (missingNavigation.count) [root addSpecifiersFromArray:missingNavigation animated:NO];
        haoge_settingsshelf_root = root; ++haoge_settingsshelf_hits;
    } @finally { --haoge_settingsshelf_busy; }
}
static void haoge_settingsshelf_schedule(id controller) {
    if (!haoge_settingsshelf_isRoot(controller) || haoge_settingsshelf_busy || haoge_settingsshelf_reconcilePending) return;
    haoge_settingsshelf_reconcilePending = YES;
    __weak PSListController *weakRoot = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        haoge_settingsshelf_reconcilePending = NO;
        haoge_settingsshelf_reconcile(weakRoot);
    });
}

static id haoge_settingsshelf_specifiersHook(id controller, SEL selector) {
    NSArray *rows = ((id (*)(id, SEL))haoge_settingsshelf_originalSpecifiers)(controller, selector);
    if (haoge_settingsshelf_busy || !haoge_settingsshelf_isRoot(controller) || ![rows isKindOfClass:NSArray.class]) return rows;
    haoge_settingsshelf_root = controller; ++haoge_settingsshelf_hits;
    // Only mutate the initial mutable list before its table is loaded, as the
    // original specifiers hook does. Live tables are changed via PSListController APIs.
    if ([controller isViewLoaded]) { haoge_settingsshelf_schedule(controller); return rows; }
    NSArray *navigation = haoge_settingsshelf_navigationRows();
    NSArray *result = [haoge_settingsshelf_state(controller) haoge_settingsshelf_transform:rows enabled:YES navigation:navigation];
    NSMutableArray *live = [rows isKindOfClass:NSMutableArray.class] ? (NSMutableArray *)rows : [rows mutableCopy];
    if (![live isEqualToArray:result]) [live setArray:result];
    return live;
}

static void haoge_settingsshelf_installBoolHook(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSString *installedKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", name];
    if ([haoge_settingsshelf_installed containsObject:installedKey] || ![cls instancesRespondToSelector:selector]) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id controller, BOOL flag) {
        ++haoge_settingsshelf_busy;
        @try { ((void (*)(id, SEL, BOOL))original)(controller, selector, flag); }
        @finally { --haoge_settingsshelf_busy; }
        if (haoge_settingsshelf_isRoot(controller)) {
            haoge_settingsshelf_root = controller;
            if (!haoge_settingsshelf_busy) haoge_settingsshelf_schedule(controller);
        }
    });
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) [haoge_settingsshelf_installed addObject:installedKey];
}
static void haoge_settingsshelf_installRootHooks(void) {
    if (!haoge_settingsshelf_rootClass) {
        for (NSString *name in @[@"PSUIPrefsListController", @"PrefsListController", @"PSGGeneralController"]) {
            Class candidate = NSClassFromString(name);
            if (candidate) { haoge_settingsshelf_rootClass = candidate; break; }
        }
    }
    Class cls = haoge_settingsshelf_rootClass;
    if (!cls) return;
    if (!haoge_settingsshelf_installed) haoge_settingsshelf_installed = [NSMutableSet set];

    NSString *specifiersKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(@selector(specifiers))];
    if (![haoge_settingsshelf_installed containsObject:specifiersKey]) {
        IMP original = NULL;
        MSHookMessageEx(cls, @selector(specifiers), (IMP)haoge_settingsshelf_specifiersHook, &original);
        haoge_settingsshelf_originalSpecifiers = original;
        if (original) [haoge_settingsshelf_installed addObject:specifiersKey];
    }

    SEL insertSelector = NSSelectorFromString(@"_insertContiguousSpecifiers:atIndex:animated:");
    NSString *insertKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(insertSelector)];
    if (![haoge_settingsshelf_installed containsObject:insertKey] && [cls instancesRespondToSelector:insertSelector]) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(id controller, NSArray *rows, NSInteger index, BOOL animated) {
            ++haoge_settingsshelf_busy;
            @try { ((void (*)(id, SEL, id, NSInteger, BOOL))original)(controller, insertSelector, rows, index, animated); }
            @finally { --haoge_settingsshelf_busy; }
            if (haoge_settingsshelf_isRoot(controller) && !haoge_settingsshelf_busy) {
                haoge_settingsshelf_root = controller; haoge_settingsshelf_schedule(controller);
            }
        });
        MSHookMessageEx(cls, insertSelector, replacement, &original);
        if (original) [haoge_settingsshelf_installed addObject:insertKey];
    }
    haoge_settingsshelf_installBoolHook(cls, @"insertMovedThirdPartySpecifiersAnimated:");
    haoge_settingsshelf_installBoolHook(cls, @"viewWillAppear:");
    haoge_settingsshelf_installBoolHook(cls, @"viewDidAppear:");

    SEL reloadSelector = @selector(reloadSpecifiers);
    NSString *reloadKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(reloadSelector)];
    if (![haoge_settingsshelf_installed containsObject:reloadKey] && [cls instancesRespondToSelector:reloadSelector]) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(id controller) {
            ++haoge_settingsshelf_busy;
            @try { ((void (*)(id, SEL))original)(controller, reloadSelector); }
            @finally { --haoge_settingsshelf_busy; }
            if (haoge_settingsshelf_isRoot(controller) && !haoge_settingsshelf_busy) {
                haoge_settingsshelf_root = controller; haoge_settingsshelf_schedule(controller);
            }
        });
        MSHookMessageEx(cls, reloadSelector, replacement, &original);
        if (original) [haoge_settingsshelf_installed addObject:reloadKey];
    }
    NSLog(@"[SettingsShelf] root-only original-style hooks installed: %@", NSStringFromClass(cls));
}

void haoge_settingsshelf_start(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_installRootHooks(); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"com.haoge.settingsshelf.regroup" object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_schedule(haoge_settingsshelf_root); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_installRootHooks(); haoge_settingsshelf_schedule(haoge_settingsshelf_root); }];
        for (NSUInteger i = 0; i < 16; ++i) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ haoge_settingsshelf_installRootHooks(); });
        haoge_settingsshelf_installRootHooks();
        NSLog(@"[SettingsShelf] original-style root-list flow active");
    });
}
