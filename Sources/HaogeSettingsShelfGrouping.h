#pragma once
#import <Foundation/Foundation.h>

@interface HaogeSettingsShelfGroupingState : NSObject
@property (nonatomic, copy, readonly) NSArray *haoge_settingsshelf_tweaks;
@property (nonatomic, copy, readonly) NSArray *haoge_settingsshelf_apps;
// Observe genuine host rows without changing the host array.
- (BOOL)haoge_settingsshelf_capture:(NSArray *)rows;
- (NSArray *)haoge_settingsshelf_transform:(NSArray *)input enabled:(BOOL)enabled navigation:(NSArray *)navigation;
@end

FOUNDATION_EXPORT NSInteger haoge_settingsshelf_entryCategory(id entry);
FOUNDATION_EXPORT BOOL haoge_settingsshelf_isNavigation(id entry);
// Input contains only retained system rows (no category navigation).
// Insert the complete category section before the connectivity section,
// leaving the Apple Account section and its original objects above it.
FOUNDATION_EXPORT NSUInteger haoge_settingsshelf_navigationInsertionIndex(NSArray *rows);
// Ranges refer to the original current array; apply them in reverse order.
FOUNDATION_EXPORT NSArray<NSValue *> *haoge_settingsshelf_rootRemovalRanges(
    NSArray *current, NSArray *desired, NSArray *navigation, BOOL *insertNavigation);
