#pragma once
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline CGSize haoge_settingsshelf_originalIconSize(CGSize original) {
    if (!isfinite(original.width) || !isfinite(original.height) ||
        original.width <= 0 || original.height <= 0 ||
        original.width > 128 || original.height > 128) return CGSizeMake(30, 30);
    return original;
}
static inline CGRect haoge_settingsshelf_iconFitRect(CGSize image, CGSize target) {
    if (!isfinite(image.width) || !isfinite(image.height) || image.width <= 0 || image.height <= 0)
        return CGRectZero;
    CGFloat factor = fmin(target.width / image.width, target.height / image.height);
    CGSize size = CGSizeMake(image.width * factor, image.height * factor);
    return CGRectMake((target.width - size.width) / 2, (target.height - size.height) / 2,
                      size.width, size.height);
}
