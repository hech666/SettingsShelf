#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSArray *haoge_settingsshelf_customizationEntries(void);
// Unknown identifiers and anything in the apps bucket are never customizable.
FOUNDATION_EXPORT BOOL haoge_settingsshelf_canCustomizeIdentifier(NSString *identifier);
FOUNDATION_EXPORT NSString *haoge_settingsshelf_displayName(NSString *identifier, NSString *fallback);
FOUNDATION_EXPORT UIImage *haoge_settingsshelf_customIcon(NSString *identifier);
FOUNDATION_EXPORT void haoge_settingsshelf_applyCustomization(id specifier);
FOUNDATION_EXPORT void haoge_settingsshelf_invalidateCustomization(void);
