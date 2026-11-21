#pragma once
#import <Foundation/Foundation.h>

@interface HaogeSettingsShelfGroupingState : NSObject
@property (nonatomic, copy) NSArray *haoge_settingsshelf_raw;
@property (nonatomic, copy) NSArray *haoge_settingsshelf_tweaks;
@property (nonatomic, copy) NSArray *haoge_settingsshelf_apps;
- (NSArray *)haoge_settingsshelf_transform:(NSArray *)input enabled:(BOOL)enabled navigation:(NSArray *)navigation;
@end

FOUNDATION_EXPORT NSInteger haoge_settingsshelf_entryCategory(id entry);
FOUNDATION_EXPORT BOOL haoge_settingsshelf_isNavigation(id entry);
