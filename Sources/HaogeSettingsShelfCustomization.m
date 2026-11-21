#import "HaogeSettingsShelfCustomization.h"
#import "HaogeSettingsShelfPreferences.h"
#import "HaogeSettingsShelfPaths.h"
#import "HaogeSettingsShelfRuntime.h"
#import <Preferences/PSSpecifier.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
    for (NSString *bucket in @[@"navigation", @"tweaks", @"apps"]) {
        id values = snapshot[bucket];
        if (![values isKindOfClass:NSArray.class]) continue;
        for (id specifier in values) {
            if (![specifier isKindOfClass:PSSpecifier.class]) continue;
            NSString *identifier = [specifier respondsToSelector:@selector(identifier)] ? [specifier identifier] : nil;
            if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) continue;
            if ([specifier respondsToSelector:@selector(cellType)] && [specifier cellType] == 0) continue;
            if ([identifier isEqualToString:@"com.haoge.settingsshelf.category.group"]) continue;
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

NSString *haoge_settingsshelf_displayName(NSString *identifier, NSString *fallback) {
    if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) return fallback ?: @"";
    id names = haoge_settingsshelf_preferenceValue(@"entryNames");
    id value = [names isKindOfClass:NSDictionary.class] ? names[identifier] : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : (fallback ?: identifier);
}

UIImage *haoge_settingsshelf_customIcon(NSString *identifier) {
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

void haoge_settingsshelf_applyCustomization(id value) {
    if (![value isKindOfClass:PSSpecifier.class]) return;
    PSSpecifier *specifier = (PSSpecifier *)value;
    NSMutableDictionary *state = objc_getAssociatedObject(specifier, &haoge_settingsshelf_originalSpecifierStateKey);
    if (!state) {
        id name = haoge_settingsshelf_specifierName(specifier);
        id label = [specifier propertyForKey:@"label"];
        id icon = [specifier propertyForKey:@"iconImage"];
        state = [@{@"name":name ?: NSNull.null, @"label":label ?: NSNull.null,
                   @"iconImage":icon ?: NSNull.null} mutableCopy];
        objc_setAssociatedObject(specifier, &haoge_settingsshelf_originalSpecifierStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *identifier = [specifier respondsToSelector:@selector(identifier)] ? [specifier identifier] : nil;
    if (!identifier.length) return;
    id rawName = state[@"name"] == NSNull.null ? state[@"label"] : state[@"name"];
    NSString *fallback = [rawName isKindOfClass:NSString.class] ? rawName : identifier;
    NSString *name = haoge_settingsshelf_displayName(identifier, fallback);
    if ([specifier respondsToSelector:@selector(setName:)])
        ((void (*)(id, SEL, id))objc_msgSend)(specifier, @selector(setName:), name);
    [specifier setProperty:name forKey:@"label"];

    UIImage *icon = haoge_settingsshelf_customIcon(identifier);
    if (icon) [specifier setProperty:icon forKey:@"iconImage"];
    else {
        id originalIcon = state[@"iconImage"];
        [specifier setProperty:(originalIcon == NSNull.null ? nil : originalIcon) forKey:@"iconImage"];
    }
}

void haoge_settingsshelf_invalidateCustomization(void) {
    [haoge_settingsshelf_iconCache() removeAllObjects];
}
