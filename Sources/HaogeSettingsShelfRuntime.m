#import "HaogeSettingsShelfRuntime.h"
#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfPaths.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char HaogeSettingsShelfStateKey;
static __weak PSListController *haoge_settingsshelf_lastRoot;
static NSHashTable *haoge_settingsshelf_roots;
static NSMutableSet *haoge_settingsshelf_installed;
static NSArray *haoge_settingsshelf_navigation;
static NSUInteger haoge_settingsshelf_hits;
static __thread NSUInteger haoge_settingsshelf_busy;

static HaogeSettingsShelfGroupingState *haoge_settingsshelf_state(id root) {
    HaogeSettingsShelfGroupingState *state = objc_getAssociatedObject(root, &HaogeSettingsShelfStateKey);
    if (!state) {
        state = [HaogeSettingsShelfGroupingState new];
        objc_setAssociatedObject(root, &HaogeSettingsShelfStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static BOOL haoge_settingsshelf_isRoot(id controller, NSArray *rows) {
    if (objc_getAssociatedObject(controller, &HaogeSettingsShelfStateKey)) return YES;
    NSString *name = NSStringFromClass([controller class]);
    if ([name containsString:@"PrefsListController"] || [name isEqualToString:@"PreferencesRootController"]) return YES;
    for (id row in rows) {
        if (![row isKindOfClass:PSSpecifier.class]) continue;
        NSString *identifier = [row identifier];
        if ([identifier isEqualToString:@"WIRELESS_GROUP"] || [identifier isEqualToString:@"THIRD_PARTY_GROUP"] ||
            [identifier isEqualToString:@"com.haoge.settingsshelf.category.group"]) return YES;
    }
    return NO;
}
static NSArray *haoge_settingsshelf_navigationRows(void) {
    if (haoge_settingsshelf_navigation.count == 3) return haoge_settingsshelf_navigation;
    Class detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    if (!detail) {
        NSString *path = haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle");
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        NSError *error = nil;
        if (![bundle isLoaded] && ![bundle loadAndReturnError:&error]) {
            NSLog(@"[SettingsShelf] preference bundle unavailable: %@", error.localizedDescription); return @[];
        }
        detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    }
    if (!detail) return @[]; // Never hide real rows without a usable destination.
    NSMutableArray *rows = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"越狱插件和应用软件"];
    group.identifier = @"com.haoge.settingsshelf.category.group"; [rows addObject:group];
    for (NSString *category in @[@"tweaks", @"apps"]) {
        BOOL apps = [category isEqualToString:@"apps"];
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:apps ? @"应用软件" : @"越狱插件"
            target:nil set:nil get:nil detail:detail cell:PSLinkCell edit:nil];
        row.identifier = [@"com.haoge.settingsshelf.category." stringByAppendingString:category];
        [row setProperty:category forKey:@"HaogeSettingsShelfCategory"];
        // The destination is an already-loaded Class. Do not overwrite `detail`
        // with an NSString or give the link a conflicting lazy-bundle value.
        NSString *file = apps ? @"HaogeSettingsShelfApps@2x.png" : @"HaogeSettingsShelfTweaks@2x.png";
        UIImage *image = [UIImage imageWithContentsOfFile:[haoge_settingsshelf_resourcePath(
            @"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle") stringByAppendingPathComponent:file]];
        if (image.CGImage) [row setProperty:[UIImage imageWithCGImage:image.CGImage scale:2 orientation:UIImageOrientationUp] forKey:@"iconImage"];
        [rows addObject:row];
    }
    haoge_settingsshelf_navigation = [rows copy]; return haoge_settingsshelf_navigation;
}

NSDictionary *haoge_settingsshelf_snapshot(void) {
    if (![NSThread isMainThread]) return @{};
    HaogeSettingsShelfGroupingState *state = haoge_settingsshelf_lastRoot ? haoge_settingsshelf_state(haoge_settingsshelf_lastRoot) : nil;
    return @{@"loaded":@YES, @"root":haoge_settingsshelf_lastRoot ? NSStringFromClass(haoge_settingsshelf_lastRoot.class) : @"",
        @"hits":@(haoge_settingsshelf_hits), @"tweaks":state.haoge_settingsshelf_tweaks ?: @[], @"apps":state.haoge_settingsshelf_apps ?: @[]};
}

static NSMutableArray *haoge_settingsshelf_transform(id root, NSArray *original) {
    if (![NSThread isMainThread] || ![original isKindOfClass:NSArray.class] || !haoge_settingsshelf_isRoot(root, original)) return (id)original;
    [haoge_settingsshelf_roots addObject:root]; haoge_settingsshelf_lastRoot = root; ++haoge_settingsshelf_hits;
    NSArray *result = [haoge_settingsshelf_state(root) haoge_settingsshelf_transform:original
        enabled:YES navigation:haoge_settingsshelf_navigationRows()];
    NSMutableArray *live = [original isKindOfClass:NSMutableArray.class] ? (id)original : [original mutableCopy];
    // PSListController table data uses its retained array, not only the getter's
    // returned value. Mutate that live array instead of returning an ignored copy.
    if (![live isEqualToArray:result]) [live setArray:result];
    return live;
}
static void haoge_settingsshelf_regroup(PSListController *root) {
    if (!root || ![NSThread isMainThread] || haoge_settingsshelf_busy) return;
    ++haoge_settingsshelf_busy;
    @try {
        NSMutableArray *rows = haoge_settingsshelf_transform(root, [root specifiers]);
        if (rows) [root setSpecifiers:rows];
        if (root.isViewLoaded) [root.table reloadData];
    } @finally { --haoge_settingsshelf_busy; }
}
static void haoge_settingsshelf_schedule(PSListController *root) {
    __weak PSListController *weakRoot = root;
    dispatch_async(dispatch_get_main_queue(), ^{ haoge_settingsshelf_regroup(weakRoot); });
}

static BOOL haoge_settingsshelf_owns(Class cls, SEL selector) {
    unsigned count = 0; Method *methods = class_copyMethodList(cls, &count); BOOL found = NO;
    for (unsigned i = 0; i < count; ++i) if (method_getName(methods[i]) == selector) { found = YES; break; }
    free(methods); return found;
}
static void haoge_settingsshelf_install(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!cls || !haoge_settingsshelf_owns(cls, selector)) return;
    NSString *key = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", name];
    if ([haoge_settingsshelf_installed containsObject:key]) return;
    __block IMP original = NULL; IMP replacement = NULL;
    if ([name isEqualToString:@"specifiers"]) {
        replacement = imp_implementationWithBlock(^id(id controller) {
            BOOL nested = haoge_settingsshelf_busy != 0; ++haoge_settingsshelf_busy; id rows = nil;
            @try { rows = ((id (*)(id, SEL))original)(controller, selector); }
            @finally { --haoge_settingsshelf_busy; }
            if (nested) return rows;
            ++haoge_settingsshelf_busy;
            @try {
                NSMutableArray *live = haoge_settingsshelf_transform(controller, rows);
                if (live != rows && haoge_settingsshelf_isRoot(controller, rows)) [controller setSpecifiers:live];
                return live;
            } @finally { --haoge_settingsshelf_busy; }
        });
    } else if ([name isEqualToString:@"setSpecifiers:"]) {
        replacement = imp_implementationWithBlock(^(id controller, NSArray *rows) {
            BOOL nested = haoge_settingsshelf_busy != 0; ++haoge_settingsshelf_busy;
            @try {
                id live = nested ? rows : haoge_settingsshelf_transform(controller, rows);
                ((void (*)(id, SEL, id))original)(controller, selector, live);
            } @finally { --haoge_settingsshelf_busy; }
        });
    } else if ([name isEqualToString:@"_insertContiguousSpecifiers:atIndex:animated:"]) {
        replacement = imp_implementationWithBlock(^(id controller, NSArray *rows, NSInteger index, BOOL animated) {
            BOOL root = haoge_settingsshelf_isRoot(controller, nil);
            ++haoge_settingsshelf_busy;
            @try {
                // Preserve the exact insertion index and animation flag. The
                // system performs a UITableView batch update here; only regroup
                // after the original insertion has fully returned.
                ((void (*)(id, SEL, id, NSInteger, BOOL))original)(controller, selector, rows, index, animated);
            } @finally { --haoge_settingsshelf_busy; }
            if (root) haoge_settingsshelf_schedule(controller);
        });
    } else {
        // All other installed methods here have exactly one BOOL argument.
        replacement = imp_implementationWithBlock(^(id controller, BOOL animated) {
            ++haoge_settingsshelf_busy;
            @try { ((void (*)(id, SEL, BOOL))original)(controller, selector, animated); }
            @finally { --haoge_settingsshelf_busy; }
            if (haoge_settingsshelf_isRoot(controller, nil)) haoge_settingsshelf_schedule(controller);
        });
    }
    if (replacement) {
        MSHookMessageEx(cls, selector, replacement, &original);
        if (original) [haoge_settingsshelf_installed addObject:key];
    }
}
static void haoge_settingsshelf_installAll(void) {
    for (NSString *name in @[@"PSListController", @"PSUIPrefsListController", @"PrefsListController", @"PreferencesRootController"]) {
        Class cls = NSClassFromString(name);
        for (NSString *selector in @[@"specifiers", @"setSpecifiers:", @"viewWillAppear:", @"viewDidAppear:",
            @"insertMovedThirdPartySpecifiersAnimated:", @"_insertContiguousSpecifiers:atIndex:animated:"])
            haoge_settingsshelf_install(cls, selector);
    }
}
static void haoge_settingsshelf_visit(UIViewController *controller, NSMutableSet *visited) {
    if (!controller || visited.count > 80 || [visited containsObject:controller]) return;
    [visited addObject:controller];
    if ([controller isKindOfClass:NSClassFromString(@"PSListController")] && controller.isViewLoaded) {
        NSArray *rows = [(PSListController *)controller specifiers];
        if (haoge_settingsshelf_isRoot(controller, rows)) haoge_settingsshelf_regroup((id)controller);
    }
    for (UIViewController *child in controller.childViewControllers) haoge_settingsshelf_visit(child, visited);
    haoge_settingsshelf_visit(controller.presentedViewController, visited);
}
static void haoge_settingsshelf_discover(void) {
    haoge_settingsshelf_installAll();
    NSMutableSet *visited = [NSMutableSet set];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) haoge_settingsshelf_visit(window.rootViewController, visited);
    }
}
void haoge_settingsshelf_start(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        haoge_settingsshelf_roots = [NSHashTable weakObjectsHashTable];
        haoge_settingsshelf_installed = [NSMutableSet set];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ haoge_settingsshelf_installAll(); });
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"com.haoge.settingsshelf.regroup" object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_discover(); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_discover(); }];
        for (NSUInteger i = 0; i < 16; ++i) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ haoge_settingsshelf_discover(); });
        NSLog(@"[SettingsShelf] always-on grouping runtime loaded");
    });
}
