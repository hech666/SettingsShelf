#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSArray * _Nullable (^HaogeSettingsShelfInventoryRowGenerator)(NSDictionary *descriptor, BOOL *success);

// Returns validated, sorted PreferenceLoader descriptors with keys
// identifier/title/name/entry/bundlePath. A nil result or complete=NO is
// incomplete and must not replace the last-known-good inventory.
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable haoge_settingsshelf_inventoryDescriptors(
    NSString *preferencesDirectory, NSString *preferenceBundlesDirectory,
    NSString *systemPreferenceBundlesDirectory, BOOL *complete);

// Generates rows transactionally, removes duplicate identifiers, then sorts
// by localized case-insensitive row name. A failed generator returns nil.
FOUNDATION_EXPORT NSArray * _Nullable haoge_settingsshelf_inventoryBuildRows(
    NSArray<NSDictionary *> *descriptors, HaogeSettingsShelfInventoryRowGenerator generator,
    BOOL *complete);
FOUNDATION_EXPORT BOOL haoge_settingsshelf_inventoryCommitRows(
    NSArray * _Nullable __strong * _Nonnull lastKnownGood, NSArray * _Nullable candidate, BOOL complete);
// A native row's target belongs to its live generating controller only.
FOUNDATION_EXPORT NSArray *haoge_settingsshelf_inventoryRowsForOwner(
    NSArray * _Nullable rows, id _Nullable owner, id _Nullable requester);
NS_ASSUME_NONNULL_END
