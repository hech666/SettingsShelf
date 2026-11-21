#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#define HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN CFSTR("com.haoge.settingsshelf")
#define HAOGE_SETTINGSSHELF_REGROUP_NOTIFICATION @"com.haoge.settingsshelf.regroup"
#define HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION @"com.haoge.settingsshelf.preferences-changed"

static inline BOOL haoge_settingsshelf_preferenceBool(NSString *key) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) return NO;
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    BOOL result = value ? [(__bridge id)value respondsToSelector:@selector(boolValue)] && [(__bridge id)value boolValue] : NO;
    if (value) CFRelease(value);
    return result;
}

static inline id haoge_settingsshelf_preferenceValue(NSString *key) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) return nil;
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    return value ? CFBridgingRelease(value) : nil;
}

static inline BOOL haoge_settingsshelf_setPreferenceValue(NSString *key, id value) {
    if (![key isKindOfClass:NSString.class] || key.length == 0) return NO;
    if (value && !CFPropertyListIsValid((__bridge CFPropertyListRef)value, kCFPropertyListXMLFormat_v1_0)) return NO;
    CFPropertyListRef previous = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                            HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             value ? (__bridge CFPropertyListRef)value : NULL,
                             HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    BOOL synchronized = CFPreferencesAppSynchronize(HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    if (!synchronized) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, previous, HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
        CFPreferencesAppSynchronize(HAOGE_SETTINGSSHELF_PREFERENCES_DOMAIN);
    }
    if (previous) CFRelease(previous);
    return synchronized;
}
