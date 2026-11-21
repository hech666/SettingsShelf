#import "HaogeSettingsShelfCategoryListController.h"
#import "../Sources/HaogeSettingsShelfPreferences.h"
#import "../Sources/HaogeSettingsShelfSnapshot.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

static NSString *haoge_settingsshelf_categoryDisplayName(NSString *identifier, NSString *fallback) {
    NSString *(*function)(NSString *, NSString *) = (NSString *(*)(NSString *, NSString *))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_displayName");
    return function ? function(identifier, fallback) : fallback;
}
static void haoge_settingsshelf_categoryApply(id specifier) {
    void (*function)(id) = (void (*)(id))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_applyCustomization");
    if (function) function(specifier);
}
static void haoge_settingsshelf_categoryNotify(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAOGE_SETTINGSSHELF_REGROUP_NOTIFICATION object:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION, NULL, NULL, true);
}

@implementation HaogeSettingsShelfCategoryListController {
    NSArray *_haoge_settingsshelf_renderedItems;
    BOOL _haoge_settingsshelf_visible;
}
- (NSString *)haoge_settingsshelf_categoryKey {
    return [[self.specifier propertyForKey:@"HaogeSettingsShelfCategory"] isEqualToString:@"apps"] ? @"apps" : @"tweaks";
}
- (NSDictionary *)haoge_settingsshelf_snapshot {
    NSDictionary *(*provider)(void) = (NSDictionary *(*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_snapshot");
    id value = provider ? provider() : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
- (NSArray *)haoge_settingsshelf_categoryItems {
    if ([[self haoge_settingsshelf_categoryKey] isEqualToString:@"apps"])
        return [self haoge_settingsshelf_snapshot][@"apps"] ?: @[];
    NSArray *(*provider)(PSListController *) = (NSArray *(*)(PSListController *))dlsym(
        RTLD_DEFAULT, "haoge_settingsshelf_tweakInventoryForController");
    id rows = provider ? provider(self) : nil;
    // Plugin inventory is generated independently from partial root observations.
    return [rows isKindOfClass:NSArray.class] ? rows : @[];
}
- (void)haoge_settingsshelf_setSwitch:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"HaogeSettingsShelfPreferenceKey"];
    BOOL requested = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    if (!haoge_settingsshelf_setPreferenceValue(key, @(requested))) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:@"设置未能同步到偏好存储。请重试。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
        return;
    }
    haoge_settingsshelf_categoryNotify();
}
- (id)haoge_settingsshelf_getSwitch:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"HaogeSettingsShelfPreferenceKey"];
    return @(haoge_settingsshelf_preferenceBool(key));
}
- (PSSpecifier *)haoge_settingsshelf_switch:(NSString *)title key:(NSString *)key {
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:title target:self
        set:@selector(haoge_settingsshelf_setSwitch:specifier:) get:@selector(haoge_settingsshelf_getSwitch:)
        detail:nil cell:PSSwitchCell edit:nil];
    [row setProperty:key forKey:@"HaogeSettingsShelfPreferenceKey"];
    return row;
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSString *category = [self haoge_settingsshelf_categoryKey];
        BOOL apps = [category isEqualToString:@"apps"];
        NSString *heading = apps ? @"应用软件" : haoge_settingsshelf_categoryDisplayName(@"com.haoge.settingsshelf.category.tweaks", @"越狱插件");
        self.title = heading;
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:heading]];
        NSArray *items = [self haoge_settingsshelf_categoryItems];
        _haoge_settingsshelf_renderedItems = items;
        for (id entry in items) {
            if (![entry isKindOfClass:PSSpecifier.class]) continue;
            if (!apps) haoge_settingsshelf_categoryApply(entry);
            [rows addObject:entry];
        }
        if (rows.count == 1) {
            PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
            [empty setProperty:@"尚未捕获到设置项目。返回设置首页等待加载，再进入分类。" forKey:@"footerText"];
            [rows addObject:empty];
        }
        if (!apps) {
            [rows addObject:[PSSpecifier groupSpecifierWithName:@"附加功能"]];
            [rows addObject:[self haoge_settingsshelf_switch:@"屏蔽部件与维修记录" key:@"suppressBatteryServiceWarnings"]];
            [rows addObject:[self haoge_settingsshelf_switch:@"屏蔽系统更新提示" key:@"suppressSoftwareUpdatePrompt"]];
            PSSpecifier *customization = [PSSpecifier preferenceSpecifierNamed:@"自定义名称与图标"
                target:nil set:nil get:nil detail:NSClassFromString(@"HaogeSettingsShelfCustomizationListController")
                cell:PSLinkCell edit:nil];
            [rows addObject:customization];
        }
        _specifiers = rows;
    }
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(haoge_settingsshelf_snapshotChanged:)
        name:HAOGE_SETTINGSSHELF_SNAPSHOT_CHANGED_NOTIFICATION object:nil];
}
- (void)haoge_settingsshelf_reloadCategory {
    // Invalidate this controller's own cache; the native controller owns the
    // list/table transaction. Never edit an array already in use by Preferences.
    _specifiers = nil;
    [self reloadSpecifiers];
}
- (void)haoge_settingsshelf_snapshotChanged:(__unused NSNotification *)notification {
    if (!_haoge_settingsshelf_visible) return;
    NSArray *items = [self haoge_settingsshelf_categoryItems];
    if (!haoge_settingsshelf_sameRows(_haoge_settingsshelf_renderedItems, items)) [self haoge_settingsshelf_reloadCategory];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self haoge_settingsshelf_reloadCategory];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _haoge_settingsshelf_visible = YES;
    [self haoge_settingsshelf_snapshotChanged:nil];
}
- (void)viewWillDisappear:(BOOL)animated {
    _haoge_settingsshelf_visible = NO;
    [super viewWillDisappear:animated];
}
@end
