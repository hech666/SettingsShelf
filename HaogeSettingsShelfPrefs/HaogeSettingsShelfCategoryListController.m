#import "HaogeSettingsShelfCategoryListController.h"
#import <dlfcn.h>

@implementation HaogeSettingsShelfCategoryListController
- (NSDictionary *)haoge_settingsshelf_snapshot {
    NSDictionary *(*provider)(void) = (NSDictionary *(*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_snapshot");
    id value = provider ? provider() : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        BOOL apps = [[self.specifier propertyForKey:@"HaogeSettingsShelfCategory"] isEqualToString:@"apps"];
        NSString *heading = apps ? @"应用软件" : @"越狱插件";
        self.title = heading;
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:heading]];
        NSArray *items = [self haoge_settingsshelf_snapshot][apps ? @"apps" : @"tweaks"];
        for (id entry in items) if ([entry isKindOfClass:PSSpecifier.class]) [rows addObject:entry];
        // Keep the exact PSSpecifier object and target. PreferenceLoader's lazy
        // bundle, callbacks, icon metadata and app deep links must not be rebuilt.
        if (rows.count == 1) {
            PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
            [empty setProperty:@"尚未捕获到设置项目。返回设置首页等待加载，再进入分类。" forKey:@"footerText"];
            [rows addObject:empty];
        }
        _specifiers = rows;
    }
    return _specifiers;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; [self reloadSpecifiers];
}
@end
