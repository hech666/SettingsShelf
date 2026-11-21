#pragma once
#import <Foundation/Foundation.h>

#define HAOGE_SETTINGSSHELF_SNAPSHOT_CHANGED_NOTIFICATION @"com.haoge.settingsshelf.snapshot-changed"

// Compare by identity: a new specifier for the same identifier may carry a
// different target, lazy loader, or action. Both sides use this criterion.
static inline BOOL haoge_settingsshelf_sameRows(NSArray *left, NSArray *right) {
    if (left == right) return YES;
    if (left.count != right.count) return NO;
    for (NSUInteger i = 0; i < left.count; ++i)
        if (left[i] != right[i]) return NO;
    return YES;
}
