#import "HaogeSettingsShelfConfig.h"
#import "HaogeSettingsShelfPreferences.h"

@interface HaogeSettingsShelfConfig ()
@property (atomic, copy) NSDictionary *snapshot;
@property (nonatomic, strong) dispatch_queue_t reloadQueue;
@end

static void haoge_settingsshelf_preferencesDidChange(CFNotificationCenterRef center __attribute__((unused)), void *observer,
                                          CFStringRef name __attribute__((unused)), const void *object __attribute__((unused)), CFDictionaryRef info __attribute__((unused))) {
    HaogeSettingsShelfConfig *config = (__bridge HaogeSettingsShelfConfig *)observer;
    dispatch_async(config.reloadQueue, ^{
        [config haoge_settingsshelf_reload];
    });
}

@implementation HaogeSettingsShelfConfig

+ (instancetype)haoge_settingsshelf_shared {
    static HaogeSettingsShelfConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reloadQueue = dispatch_queue_create("com.haoge.settingsshelf.preferences", DISPATCH_QUEUE_SERIAL);
        [self haoge_settingsshelf_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self, haoge_settingsshelf_preferencesDidChange,
            (__bridge CFStringRef)HaogeSettingsShelfPreferencesChanged, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Close the window between the first read and observer registration.
        dispatch_async(_reloadQueue, ^{ [self haoge_settingsshelf_reload]; });
    }
    return self;
}

- (void)haoge_settingsshelf_reload {
    self.snapshot = haoge_settingsshelf_readPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HaogeSettingsShelfPreferencesChanged object:self];
    });
}

- (id)haoge_settingsshelf_valueForKey:(NSString *)key defaultValue:(id)defaultValue {
    return self.snapshot[key] ?: defaultValue;
}

- (BOOL)haoge_settingsshelf_isEnabled {
    id value = [self haoge_settingsshelf_valueForKey:@"enabled" defaultValue:@(NO)];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

- (void)dealloc {
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            (__bridge const void *)self);
}

@end
