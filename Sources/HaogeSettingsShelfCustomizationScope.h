#pragma once
#import <Foundation/Foundation.h>

// An explicit bucket is required; unknown entries and all app entries fail closed.
static inline BOOL haoge_settingsshelf_customizationScopeAllows(id identifier, NSString *bucket) {
    if (![identifier isKindOfClass:NSString.class] || [identifier length] == 0) return NO;
    if ([bucket isEqualToString:@"apps"]) return NO;
    if ([identifier hasPrefix:@"com.haoge.settingsshelf.category."])
        return [identifier isEqualToString:@"com.haoge.settingsshelf.category.tweaks"] &&
            ([bucket isEqualToString:@"navigation"] || [bucket isEqualToString:@"tweaks"]);
    return [bucket isEqualToString:@"tweaks"];
}
