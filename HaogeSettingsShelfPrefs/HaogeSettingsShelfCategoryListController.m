#import "HaogeSettingsShelfCategoryListController.h"
#import "../Sources/HaogeSettingsShelfPreferences.h"
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

@implementation HaogeSettingsShelfCategoryListController
- (NSDictionary *)haoge_settingsshelf_snapshot {
    NSDictionary *(*provider)(void) = (NSDictionary *(*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_snapshot");
    id value = provider ? provider() : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
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
        BOOL apps = [[self.specifier propertyForKey:@"HaogeSettingsShelfCategory"] isEqualToString:@"apps"];
        NSString *category = apps ? @"apps" : @"tweaks";
        NSString *fallbackHeading = apps ? @"应用软件" : @"越狱插件";
        NSString *heading = haoge_settingsshelf_categoryDisplayName([@"com.haoge.settingsshelf.category." stringByAppendingString:category], fallbackHeading);
        self.title = heading;
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:heading]];
        NSArray *items = [self haoge_settingsshelf_snapshot][category];
        for (id entry in items) {
            if (![entry isKindOfClass:PSSpecifier.class]) continue;
            haoge_settingsshelf_categoryApply(entry);
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
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
}
@end
