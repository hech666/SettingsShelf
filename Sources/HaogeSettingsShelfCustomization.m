#import "HaogeSettingsShelfCustomization.h"
#import "HaogeSettingsShelfPreferences.h"
#import "HaogeSettingsShelfPaths.h"
#import "HaogeSettingsShelfRuntime.h"
#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfCustomizationScope.h"
#import "HaogeSettingsShelfIconGeometry.h"
#import <Preferences/PSSpecifier.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL haoge_settingsshelf_bucketContainsIdentifier(NSDictionary *snapshot, NSString *bucket, NSString *identifier) {
    id rows = snapshot[bucket];
    if (![rows isKindOfClass:NSArray.class]) return NO;
    for (id row in rows) {
        if (![row respondsToSelector:@selector(identifier)]) continue;
        id value = [row identifier];
        if ([value isKindOfClass:NSString.class] && [value isEqualToString:identifier]) return YES;
    }
    return NO;
}

BOOL haoge_settingsshelf_canCustomizeIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return NO;
    NSDictionary *snapshot = haoge_settingsshelf_snapshot();
    if (haoge_settingsshelf_bucketContainsIdentifier(snapshot, @"apps", identifier)) return NO;
    if (haoge_settingsshelf_customizationScopeAllows(identifier, @"navigation")) return YES;
    return haoge_settingsshelf_customizationScopeAllows(identifier, @"tweaks") &&
        haoge_settingsshelf_bucketContainsIdentifier(snapshot, @"tweaks", identifier);
}

static char haoge_settingsshelf_originalSpecifierStateKey;
static NSCache<NSString *, UIImage *> *haoge_settingsshelf_customIconCache;

static NSCache<NSString *, UIImage *> *haoge_settingsshelf_iconCache(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        haoge_settingsshelf_customIconCache = [NSCache new];
        haoge_settingsshelf_customIconCache.totalCostLimit = 16 * 1024 * 1024;
        haoge_settingsshelf_customIconCache.countLimit = 64;
    });
    return haoge_settingsshelf_customIconCache;
}
static void haoge_settingsshelf_cacheChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    [haoge_settingsshelf_iconCache() removeAllObjects];
}
static void haoge_settingsshelf_installCacheObservers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            haoge_settingsshelf_cacheChanged, (__bridge CFStringRef)HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION,
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserverForName:HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { [haoge_settingsshelf_iconCache() removeAllObjects]; }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { [haoge_settingsshelf_iconCache() removeAllObjects]; }];
    });
}

static NSString *haoge_settingsshelf_customizationDirectory(void) {
    static NSString *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ directory = haoge_settingsshelf_resourcePath(@"/var/mobile/Haoge/SettingsShelf"); });
    return directory;
}

static id haoge_settingsshelf_specifierName(id specifier) {
    if ([specifier respondsToSelector:@selector(name)])
        return ((id (*)(id, SEL))objc_msgSend)(specifier, @selector(name));
    return nil;
}

static UIImage *haoge_settingsshelf_decodeIcon(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    size_t count = CGImageSourceGetCount(source);
    if (count == 0) { CFRelease(source); return nil; }
    NSUInteger frames = MIN((NSUInteger)count, (NSUInteger)24);
    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:frames];
    NSTimeInterval duration = 0;
    for (NSUInteger index = 0; index < frames; ++index) {
        CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, index,
            (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                        (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                        (NSString *)kCGImageSourceThumbnailMaxPixelSize:@180});
        if (!cgImage) continue;
        UIImage *image = [UIImage imageWithCGImage:cgImage scale:3.0 orientation:UIImageOrientationUp];
        [images addObject:image];
        CGImageRelease(cgImage);
        CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
        NSDictionary *dictionary = properties ? CFBridgingRelease(properties) : nil;
        NSDictionary *gif = [dictionary[(NSString *)kCGImagePropertyGIFDictionary] isKindOfClass:NSDictionary.class]
            ? dictionary[(NSString *)kCGImagePropertyGIFDictionary] : nil;
        NSTimeInterval frameDuration = [gif[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
        if (frameDuration <= 0) frameDuration = [gif[(NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
        duration += MAX(frameDuration, 0.08);
    }
    CFRelease(source);
    if (images.count == 0) return nil;
    return images.count > 1 ? [UIImage animatedImageWithImages:images duration:MAX(duration, 0.1)] : images.firstObject;
}

NSArray *haoge_settingsshelf_customizationEntries(void) {
    NSDictionary *snapshot = haoge_settingsshelf_snapshot();
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *bucket in @[@"navigation", @"tweaks"]) {
        id values = snapshot[bucket];
        if (![values isKindOfClass:NSArray.class]) continue;
        for (id specifier in values) {
            if (![specifier isKindOfClass:PSSpecifier.class]) continue;
            NSString *identifier = [specifier respondsToSelector:@selector(identifier)] ? [specifier identifier] : nil;
            if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) continue;
            if ([specifier respondsToSelector:@selector(cellType)] && [specifier cellType] == 0) continue;
            if (!haoge_settingsshelf_customizationScopeAllows(identifier, bucket) ||
                !haoge_settingsshelf_canCustomizeIdentifier(identifier)) continue;
            NSMutableDictionary *state = objc_getAssociatedObject(specifier, &haoge_settingsshelf_originalSpecifierStateKey);
            id originalName = state ? (state[@"name"] == NSNull.null ? state[@"label"] : state[@"name"]) : haoge_settingsshelf_specifierName(specifier);
            if (![originalName isKindOfClass:NSString.class] || [originalName length] == 0)
                originalName = state ? state[@"label"] : [specifier propertyForKey:@"label"];
            if (![originalName isKindOfClass:NSString.class] || [originalName length] == 0) originalName = identifier;
            id originalIcon = state ? state[@"iconImage"] : [specifier propertyForKey:@"iconImage"];
            if (originalIcon == NSNull.null) originalIcon = nil;
            NSMutableDictionary *entry = [@{@"identifier":identifier,
                                             @"fallbackName":originalName,
                                             @"name":haoge_settingsshelf_displayName(identifier, originalName)} mutableCopy];
            UIImage *icon = haoge_settingsshelf_customIcon(identifier);
            if (!icon && [originalIcon isKindOfClass:UIImage.class]) icon = originalIcon;
            entry[@"iconImage"] = icon ?: NSNull.null;
            [result addObject:[entry copy]];
        }
    }
    return [result copy];
}

static NSString *haoge_settingsshelf_scopedDisplayName(NSString *identifier, NSString *fallback) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return fallback ?: @"";
    id names = haoge_settingsshelf_preferenceValue(@"entryNames");
    id value = [names isKindOfClass:NSDictionary.class] ? names[identifier] : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : (fallback ?: identifier);
}

NSString *haoge_settingsshelf_displayName(NSString *identifier, NSString *fallback) {
    if (!haoge_settingsshelf_canCustomizeIdentifier(identifier)) return fallback ?: @"";
    return haoge_settingsshelf_scopedDisplayName(identifier, fallback);
}

static UIImage *haoge_settingsshelf_scopedCustomIcon(NSString *identifier) {
    haoge_settingsshelf_installCacheObservers();
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return nil;
    id icons = haoge_settingsshelf_preferenceValue(@"entryIcons");
    id filename = [icons isKindOfClass:NSDictionary.class] ? icons[identifier] : nil;
    if (![filename isKindOfClass:NSString.class] || [filename length] == 0 ||
        ![[filename lastPathComponent] isEqualToString:filename]) return nil;
    NSString *cacheKey = [identifier stringByAppendingFormat:@"\n%@", filename];
    UIImage *cached = [haoge_settingsshelf_iconCache() objectForKey:cacheKey];
    if (cached) return cached;
    NSString *path = [haoge_settingsshelf_customizationDirectory() stringByAppendingPathComponent:filename];
    NSString *extension = path.pathExtension.lowercaseString;
    if (![@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:extension]) return nil;
    UIImage *image = haoge_settingsshelf_decodeIcon(path);
    if (image) {
        NSUInteger frames = MAX((NSUInteger)1, image.images.count);
        [haoge_settingsshelf_iconCache() setObject:image forKey:cacheKey cost:180 * 180 * 4 * frames];
    }
    return image;
}

static UIImage *haoge_settingsshelf_fitIcon(UIImage *image, UIImage *original, NSString *identifier);

UIImage *haoge_settingsshelf_customIcon(NSString *identifier) {
    if (!haoge_settingsshelf_canCustomizeIdentifier(identifier)) return nil;
    UIImage *original = nil;
    NSDictionary *snapshot = haoge_settingsshelf_snapshot();
    for (NSString *bucket in @[@"navigation", @"tweaks"]) {
        for (PSSpecifier *row in snapshot[bucket]) {
            if (![row isKindOfClass:PSSpecifier.class] || ![row.identifier isEqualToString:identifier]) continue;
            NSDictionary *state = objc_getAssociatedObject(row, &haoge_settingsshelf_originalSpecifierStateKey);
            id icon = state ? state[@"iconImage"] : [row propertyForKey:@"iconImage"];
            if ([icon isKindOfClass:UIImage.class]) original = icon;
        }
    }
    return haoge_settingsshelf_fitIcon(haoge_settingsshelf_scopedCustomIcon(identifier), original, identifier);
}

static UIImage *haoge_settingsshelf_fitIcon(UIImage *image, UIImage *original, NSString *identifier) {
    if (!image) return nil;
    CGSize target = haoge_settingsshelf_originalIconSize(original ? original.size : CGSizeZero);
    CGFloat scale = UIScreen.mainScreen.scale;
    id icons = haoge_settingsshelf_preferenceValue(@"entryIcons");
    id filename = [icons isKindOfClass:NSDictionary.class] ? icons[identifier] : nil;
    NSString *key = [NSString stringWithFormat:@"fit:%@:%@:%g:%g:%g", identifier, filename, target.width, target.height, scale];
    UIImage *cached = [haoge_settingsshelf_iconCache() objectForKey:key];
    if (cached) return cached;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = NO;
    format.scale = scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    NSArray<UIImage *> *frames = image.images.count ? image.images : @[image];
    NSMutableArray<UIImage *> *rendered = [NSMutableArray arrayWithCapacity:frames.count];
    for (UIImage *frame in frames) {
        UIImage *fitted = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
            [frame drawInRect:haoge_settingsshelf_iconFitRect(frame.size, target)];
        }];
        if (fitted) [rendered addObject:fitted];
    }
    UIImage *result = rendered.count > 1 ? [UIImage animatedImageWithImages:rendered duration:MAX(image.duration, 0.1)] : rendered.firstObject;
    if (result) {
        NSUInteger cost = (NSUInteger)(target.width * target.height * scale * scale * 4) * MAX((NSUInteger)1, rendered.count);
        [haoge_settingsshelf_iconCache() setObject:result forKey:key cost:cost];
    }
    return result;
}

void haoge_settingsshelf_applyCustomization(id value) {
    if (![value isKindOfClass:PSSpecifier.class]) return;
    PSSpecifier *specifier = (PSSpecifier *)value;
    NSString *identifier = [specifier respondsToSelector:@selector(identifier)] ? [specifier identifier] : nil;
    // Reject before capturing/restoring any state. App routing and original presentation stay untouched.
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return;
    NSDictionary *snapshot = haoge_settingsshelf_snapshot();
    if (haoge_settingsshelf_bucketContainsIdentifier(snapshot, @"apps", identifier)) return;
    BOOL navigation = haoge_settingsshelf_customizationScopeAllows(identifier, @"navigation");
    if (!navigation && (!haoge_settingsshelf_customizationScopeAllows(identifier, @"tweaks") ||
                        haoge_settingsshelf_entryCategory(specifier) != 1)) return;
    NSMutableDictionary *state = objc_getAssociatedObject(specifier, &haoge_settingsshelf_originalSpecifierStateKey);
    if (!state) {
        id name = haoge_settingsshelf_specifierName(specifier);
        id label = [specifier propertyForKey:@"label"];
        id icon = [specifier propertyForKey:@"iconImage"];
        state = [@{@"name":name ?: NSNull.null, @"label":label ?: NSNull.null,
                   @"iconImage":icon ?: NSNull.null} mutableCopy];
        objc_setAssociatedObject(specifier, &haoge_settingsshelf_originalSpecifierStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id rawName = state[@"name"] == NSNull.null ? state[@"label"] : state[@"name"];
    NSString *fallback = [rawName isKindOfClass:NSString.class] ? rawName : identifier;
    NSString *name = haoge_settingsshelf_scopedDisplayName(identifier, fallback);
    if ([specifier respondsToSelector:@selector(setName:)])
        ((void (*)(id, SEL, id))objc_msgSend)(specifier, @selector(setName:), name);
    [specifier setProperty:name forKey:@"label"];

    id originalIcon = state[@"iconImage"];
    UIImage *icon = haoge_settingsshelf_fitIcon(haoge_settingsshelf_scopedCustomIcon(identifier),
        [originalIcon isKindOfClass:UIImage.class] ? originalIcon : nil, identifier);
    if (icon) [specifier setProperty:icon forKey:@"iconImage"];
    else {
        [specifier setProperty:(originalIcon == NSNull.null ? nil : originalIcon) forKey:@"iconImage"];
    }
}

void haoge_settingsshelf_invalidateCustomization(void) {
    [haoge_settingsshelf_iconCache() removeAllObjects];
}
