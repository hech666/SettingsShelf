#pragma once

#import <Foundation/Foundation.h>

@interface HaogeSettingsShelfConfig : NSObject
+ (instancetype)haoge_settingsshelf_shared;
- (BOOL)haoge_settingsshelf_isEnabled;
- (id)haoge_settingsshelf_valueForKey:(NSString *)key defaultValue:(id)defaultValue;
- (void)haoge_settingsshelf_reload;
@end
