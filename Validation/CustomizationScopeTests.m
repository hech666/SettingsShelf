#import <Foundation/Foundation.h>
#import "HaogeSettingsShelfCustomizationScope.h"
#import "HaogeSettingsShelfIconGeometry.h"
static NSUInteger assertions;
#define VERIFY(...) do { ++assertions; if (!(__VA_ARGS__)) { NSLog(@"FAILED line %d: %s", __LINE__, #__VA_ARGS__); return 1; } } while (0)
int main(void) { @autoreleasepool {
    VERIFY(haoge_settingsshelf_customizationScopeAllows(@"com.example.tweak", @"tweaks"));
    VERIFY(!haoge_settingsshelf_customizationScopeAllows(@"com.example.app", @"apps"));
    VERIFY(!haoge_settingsshelf_customizationScopeAllows(@"com.example.tweak", @"unknown"));
    VERIFY(!haoge_settingsshelf_customizationScopeAllows(nil, @"tweaks"));
    VERIFY(!haoge_settingsshelf_customizationScopeAllows(@42, @"tweaks"));
    VERIFY(!haoge_settingsshelf_customizationScopeAllows(@"", @"tweaks"));
    for (NSString *bucket in @[@"navigation", @"tweaks", @"apps", @"unknown"]) {
        VERIFY(!haoge_settingsshelf_customizationScopeAllows(@"com.haoge.settingsshelf.category.apps", bucket));
        VERIFY(!haoge_settingsshelf_customizationScopeAllows(@"com.haoge.settingsshelf.category.group", bucket));
    }
    VERIFY(haoge_settingsshelf_customizationScopeAllows(@"com.haoge.settingsshelf.category.tweaks", @"navigation"));
    VERIFY(CGSizeEqualToSize(haoge_settingsshelf_originalIconSize(CGSizeZero), CGSizeMake(30, 30)));
    VERIFY(CGSizeEqualToSize(haoge_settingsshelf_originalIconSize(CGSizeMake(NAN, 30)), CGSizeMake(30, 30)));
    for (NSUInteger side = 20; side <= 60; ++side) {
        CGSize original = CGSizeMake(side, side);
        VERIFY(CGSizeEqualToSize(haoge_settingsshelf_originalIconSize(original), original));
        for (NSUInteger width = 1; width <= 2500; width += 137) {
            for (NSUInteger height = 1; height <= 2500; height += 193) {
                CGRect rect = haoge_settingsshelf_iconFitRect(CGSizeMake(width, height), original);
                VERIFY(rect.origin.x >= -0.00001 && rect.origin.y >= -0.00001);
                VERIFY(CGRectGetMaxX(rect) <= side + 0.00001 && CGRectGetMaxY(rect) <= side + 0.00001);
                VERIFY(fabs(rect.size.width / rect.size.height - (double)width / height) < 0.00001);
                VERIFY(fabs(rect.origin.x * 2 + rect.size.width - side) < 0.00001);
                VERIFY(fabs(rect.origin.y * 2 + rect.size.height - side) < 0.00001);
            }
        }
    }
    NSLog(@"SettingsShelf customization scope and original icon geometry: %lu assertions passed", (unsigned long)assertions);
    return 0;
} }
