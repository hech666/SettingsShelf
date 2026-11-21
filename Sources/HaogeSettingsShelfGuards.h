#pragma once
#import <Foundation/Foundation.h>

/** Returns a filtered immutable copy only when a configured guard matches.
 *  Pass the result of the SettingsShelf transform; SettingsShelf navigation
 *  rows are always retained. With both preferences off, returns `rows` itself.
 */
FOUNDATION_EXPORT NSArray *haoge_settingsshelf_guardRootRows(NSArray *rows);
FOUNDATION_EXPORT NSArray *haoge_settingsshelf_guardRowsForFlags(NSArray *rows, BOOL repair, BOOL update);

/** Refreshes preference snapshots and idempotently hooks available target APIs.
 *  Safe to call again after a target framework/bundle has been loaded.
 */
FOUNDATION_EXPORT void haoge_settingsshelf_installGuards(void);
