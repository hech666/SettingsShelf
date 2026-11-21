#pragma once

#import <Foundation/Foundation.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#else
#import <rootless.h>
#endif

static inline NSString *haoge_settingsshelf_resourcePath(NSString *rootfsPath) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(rootfsPath);
#else
    return ROOT_PATH_NS_VAR(rootfsPath);
#endif
}
