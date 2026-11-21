#import "HaogeSettingsShelfRootListController.h"
#import "HaogeSettingsShelfCategoryListController.h"
#import <Preferences/PSSpecifier.h>
#import <dlfcn.h>

static void haoge_settingsshelf_rootApply(id specifier) {
    void (*function)(id) = (void (*)(id))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_applyCustomization");
    if (function) function(specifier);
}

@implementation HaogeSettingsShelfRootListController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSDictionary *(*provider)(void) = (NSDictionary *(*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_snapshot");
        NSDictionary *status = provider ? provider() : @{};
        NSMutableArray *rows = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"安装后默认生效"];
        NSString *message = [status[@"loaded"] boolValue]
            ? [NSString stringWithFormat:@"已收纳：越狱插件 %lu 项，应用软件 %lu 项。没有开关，旧版关闭状态不再使用。",
                (unsigned long)[status[@"tweaks"] count], (unsigned long)[status[@"apps"] count]]
            : @"收纳主库尚未加载。请完全退出系统设置后重新打开；此插件不再需要开启开关。";
        [group setProperty:message forKey:@"footerText"]; [rows addObject:group];
        for (NSString *category in @[@"tweaks", @"apps"]) {
            BOOL apps = [category isEqualToString:@"apps"];
            NSString *fallback = apps ? @"应用软件" : @"越狱插件";
            NSString *identifier = [@"com.haoge.settingsshelf.category." stringByAppendingString:category];
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:fallback
                target:nil set:nil get:nil detail:HaogeSettingsShelfCategoryListController.class cell:PSLinkCell edit:nil];
            row.identifier = identifier;
            [row setProperty:category forKey:@"HaogeSettingsShelfCategory"];
            haoge_settingsshelf_rootApply(row);
            [rows addObject:row];
        }
        PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"重新整理设置首页" target:self
            set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [refresh setButtonAction:@selector(haoge_settingsshelf_refresh)]; [rows addObject:refresh];
        _specifiers = rows;
    }
    return _specifiers;
}
- (void)haoge_settingsshelf_refresh {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.haoge.settingsshelf.regroup" object:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (PSSpecifier *row in _specifiers) if ([row.identifier hasPrefix:@"com.haoge.settingsshelf.category."]) haoge_settingsshelf_rootApply(row);
        [self reloadSpecifiers];
    });
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    for (PSSpecifier *row in _specifiers) if ([row.identifier hasPrefix:@"com.haoge.settingsshelf.category."]) haoge_settingsshelf_rootApply(row);
    [self reloadSpecifiers];
}
@end
