#import "HaogeSettingsShelfGuards.h"
#import "HaogeSettingsShelfPreferences.h"
#import <objc/runtime.h>
#if defined(HAOGE_SETTINGSSHELF_GUARD_TESTING)
// The macOS regression executable supplies an Objective-C runtime replacement.
extern void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
#else
#import <substrate.h>
#endif
#import <stdatomic.h>
#include <stdlib.h>
#include <string.h>

static atomic_bool haoge_settingsshelf_repairEnabled = ATOMIC_VAR_INIT(false);
static atomic_bool haoge_settingsshelf_updateEnabled = ATOMIC_VAR_INIT(false);
static NSMutableSet<NSString *> *haoge_settingsshelf_guardInstalled;
static NSMutableDictionary<NSString *, NSValue *> *haoge_settingsshelf_guardOriginals;
static NSObject *haoge_settingsshelf_guardLock;

static BOOL haoge_settingsshelf_repairIsEnabled(void) {
    return atomic_load_explicit(&haoge_settingsshelf_repairEnabled, memory_order_relaxed);
}
static BOOL haoge_settingsshelf_updateIsEnabled(void) {
    return atomic_load_explicit(&haoge_settingsshelf_updateEnabled, memory_order_relaxed);
}

static NSArray<NSString *> *haoge_settingsshelf_repairPropertyKeys(void) {
    return @[@"id", @"identifier", @"name", @"label", @"title", @"text",
             @"detailText", @"footerText", @"headerText", @"cellClass",
             @"headerCellClass", @"footerCellClass", @"url", @"URL", @"link"];
}
static NSArray<NSString *> *haoge_settingsshelf_repairTerms(void) {
    return @[@"importantbatterymessage", @"important_battery", @"important battery message",
             @"batteryservicesuggestion", @"battery_service", @"battery service",
             @"servicerecommended", @"service_recommended", @"service recommended",
             @"nongenuinebattery", @"nongenuine_battery", @"non-genuine battery",
             @"batteryhealthunknown", @"battery_health_unknown", @"battery health unknown",
             @"battery not trusted", @"untrusted battery", @"recalibrat",
             @"plfollowupheadercell", @"plfollowupsecondaryheadercell",
             @"significantly degraded", @"unable to verify", @"unable to determine battery health",
             @"unable to determine if your iphone battery is a genuine apple part",
             @"genuine apple battery", @"battery authenticity",
             @"无法确定iphone电池是否为正品apple部件", @"无法确定 iphone 电池是否为正品 apple 部件",
             @"非正品apple部件", @"非正品 apple 部件", @"重要电池信息",
             @"电池健康状况显著下降", @"无法验证", @"无法确定电池健康状况",
             @"重新校准", @"建议维修"];
}
static NSArray<NSString *> *haoge_settingsshelf_addItemAccessorKeys(void) {
    return @[@"applicationBundleID", @"clientIdentifier", @"containerPath",
             @"title", @"subtitle", @"localizedTitle"];
}
static NSArray<NSString *> *haoge_settingsshelf_updatePropertyKeys(void) {
    return @[@"id", @"identifier", @"cellClass", @"cell", @"detail", @"bundle",
             @"url", @"URL", @"name", @"label", @"title"];
}
static NSArray<NSString *> *haoge_settingsshelf_updatePropertyTerms(void) {
    return @[@"softwareupdate", @"software_update"];
}
static NSArray<NSString *> *haoge_settingsshelf_updateNameTerms(void) {
    return @[@"ios", @"可用", @"available"];
}

static BOOL haoge_settingsshelf_textContainsAny(NSString *text, NSArray<NSString *> *terms) {
    if (![text isKindOfClass:NSString.class] || text.length == 0) return NO;
    NSString *folded = text.lowercaseString;
    for (NSString *term in terms) {
        if ([folded rangeOfString:term.lowercaseString].location != NSNotFound) return YES;
    }
    return NO;
}

// Match string/URL/class values and nested Foundation containers without KVC.
// The depth cap also makes malformed cyclic object graphs harmless.
static BOOL haoge_settingsshelf_valueContainsTerms(id value, NSArray<NSString *> *terms, NSUInteger depth) {
    if (!value || depth > 5) return NO;
    if (class_isMetaClass(object_getClass(value))) return haoge_settingsshelf_textContainsAny(NSStringFromClass((Class)value), terms);
    if ([value isKindOfClass:NSString.class]) return haoge_settingsshelf_textContainsAny(value, terms);
    if ([value isKindOfClass:NSURL.class]) return haoge_settingsshelf_textContainsAny([value absoluteString], terms);
    if ([value isKindOfClass:NSAttributedString.class]) return haoge_settingsshelf_textContainsAny([value string], terms);
    if ([value isKindOfClass:NSDictionary.class]) {
        for (id key in value) {
            if (haoge_settingsshelf_valueContainsTerms(key, terms, depth + 1) ||
                haoge_settingsshelf_valueContainsTerms(value[key], terms, depth + 1)) return YES;
        }
        return NO;
    }
    if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSSet.class]) {
        for (id item in value) if (haoge_settingsshelf_valueContainsTerms(item, terms, depth + 1)) return YES;
    }
    return NO;
}

static char haoge_settingsshelf_typeCode(const char *type);
static BOOL haoge_settingsshelf_hasObjectMethod(id object, SEL selector, NSUInteger arguments) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != arguments) return NO;
    char result = haoge_settingsshelf_typeCode(signature.methodReturnType);
    return result == '@' || result == '#';
}
static id haoge_settingsshelf_propertyValue(id object, NSString *key) {
    SEL selector = NSSelectorFromString(@"propertyForKey:");
    if (!haoge_settingsshelf_hasObjectMethod(object, selector, 3)) return nil;
    @try {
        return ((id (*)(id, SEL, id))[object methodForSelector:selector])(object, selector, key);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}
static id haoge_settingsshelf_zeroArgumentValue(id object, SEL selector) {
    if (!haoge_settingsshelf_hasObjectMethod(object, selector, 2)) return nil;
    @try { return ((id (*)(id, SEL))[object methodForSelector:selector])(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static NSString *haoge_settingsshelf_identifier(id row) {
    id value = haoge_settingsshelf_zeroArgumentValue(row, NSSelectorFromString(@"identifier"));
    return [value isKindOfClass:NSString.class] ? value : @"";
}
static BOOL haoge_settingsshelf_isOwnNavigation(id row) {
    return [haoge_settingsshelf_identifier(row) hasPrefix:@"com.haoge.settingsshelf.category."];
}

static BOOL haoge_settingsshelf_repairRowMatches(id row) {
    if (!row) return NO;
    NSArray *terms = haoge_settingsshelf_repairTerms();
    NSString *className = NSStringFromClass([row class]);
    if (haoge_settingsshelf_textContainsAny(className, terms)) return YES;
    for (NSString *key in @[@"identifier", @"name"]) {
        if (haoge_settingsshelf_valueContainsTerms(haoge_settingsshelf_zeroArgumentValue(row, NSSelectorFromString(key)), terms, 0)) return YES;
    }
    for (NSString *key in haoge_settingsshelf_repairPropertyKeys()) {
        if (haoge_settingsshelf_valueContainsTerms(haoge_settingsshelf_propertyValue(row, key), terms, 0)) return YES;
    }
    return NO;
}

static BOOL haoge_settingsshelf_updateRowMatches(id row) {
    if (!row) return NO;
    NSArray *terms = haoge_settingsshelf_updatePropertyTerms();
    for (NSString *key in haoge_settingsshelf_updatePropertyKeys()) {
        if (haoge_settingsshelf_valueContainsTerms(haoge_settingsshelf_propertyValue(row, key), terms, 0)) return YES;
    }
    id name = haoge_settingsshelf_zeroArgumentValue(row, NSSelectorFromString(@"name"));
    NSArray *nameTerms = haoge_settingsshelf_updateNameTerms();
    return [name isKindOfClass:NSString.class] &&
        haoge_settingsshelf_textContainsAny(name, @[nameTerms[0]]) &&
        haoge_settingsshelf_textContainsAny(name, @[nameTerms[1], nameTerms[2]]);
}

static NSString *haoge_settingsshelf_stringFromItemValue(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSURL.class]) return [value absoluteString];
    if (value && class_isMetaClass(object_getClass(value))) return NSStringFromClass((Class)value);
    return nil;
}
static id haoge_settingsshelf_itemAccessorValue(id item, NSString *accessor) {
    SEL selector = NSSelectorFromString(accessor);
    if (!haoge_settingsshelf_hasObjectMethod(item, selector, 2)) return nil;
    @try { return ((id (*)(id, SEL))[item methodForSelector:selector])(item, selector); }
    @catch (__unused NSException *exception) { return nil; }
}
static BOOL haoge_settingsshelf_addItemMatches(id item) {
    NSArray *terms = haoge_settingsshelf_repairTerms();
    if (haoge_settingsshelf_valueContainsTerms(item, terms, 0) || haoge_settingsshelf_repairRowMatches(item)) return YES;
    for (NSString *accessor in haoge_settingsshelf_addItemAccessorKeys()) {
        NSString *text = haoge_settingsshelf_stringFromItemValue(haoge_settingsshelf_itemAccessorValue(item, accessor));
        if (haoge_settingsshelf_textContainsAny(text, terms) ||
            haoge_settingsshelf_textContainsAny(text, @[@"battery", @"电池"])) return YES;
    }
    return NO;
}

static BOOL haoge_settingsshelf_isGroupRow(id row) {
    SEL selector = NSSelectorFromString(@"cellType");
    if (![row respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [row methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || !signature.methodReturnLength ||
        signature.methodReturnLength > sizeof(unsigned long long) ||
        !strchr("cCsSiIlLqQB", signature.methodReturnType[0])) return NO;
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = row; invocation.selector = selector;
    unsigned long long result = 0;
    @try { [invocation invoke]; [invocation getReturnValue:&result]; }
    @catch (__unused NSException *exception) { return NO; }
    return result == 0;
}

NSArray *haoge_settingsshelf_guardRowsForFlags(NSArray *rows, BOOL repair, BOOL update) {
    if (![rows isKindOfClass:NSArray.class] || (!repair && !update)) return rows;
    NSMutableIndexSet *removals = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < rows.count; ++i) {
        id row = rows[i];
        if (haoge_settingsshelf_isOwnNavigation(row) || haoge_settingsshelf_isGroupRow(row)) continue;
        if ((repair && haoge_settingsshelf_repairRowMatches(row)) ||
            (update && haoge_settingsshelf_updateRowMatches(row))) [removals addIndex:i];
    }
    // Remove a header only when its nonempty section consists entirely of
    // suppressed rows. Mixed sections keep their original header and footer.
    for (NSUInteger i = 0; i < rows.count; ++i) {
        if (haoge_settingsshelf_isOwnNavigation(rows[i]) || !haoge_settingsshelf_isGroupRow(rows[i])) continue;
        NSUInteger end = i + 1;
        while (end < rows.count && !haoge_settingsshelf_isGroupRow(rows[end])) ++end;
        if (end > i + 1 && [removals countOfIndexesInRange:NSMakeRange(i + 1, end - i - 1)] == end - i - 1)
            [removals addIndex:i];
    }
    if (!removals.count) return rows;
    NSMutableArray *filtered = [rows mutableCopy];
    [filtered removeObjectsAtIndexes:removals];
    return [filtered copy];
}
NSArray *haoge_settingsshelf_guardRootRows(NSArray *rows) {
    return haoge_settingsshelf_guardRowsForFlags(rows, haoge_settingsshelf_repairIsEnabled(), haoge_settingsshelf_updateIsEnabled());
}

static char haoge_settingsshelf_typeCode(const char *type) {
    if (!type) return '\0';
    while (strchr("rnNoORV", *type) && *type) ++type;
    return *type;
}
static char haoge_settingsshelf_returnCode(Method method) {
    char *type = method_copyReturnType(method);
    char result = haoge_settingsshelf_typeCode(type);
    free(type);
    return result;
}
static char haoge_settingsshelf_argumentCode(Method method, unsigned int index) {
    char *type = method_copyArgumentType(method, index);
    char result = haoge_settingsshelf_typeCode(type);
    free(type);
    return result;
}
static NSString *haoge_settingsshelf_installKey(Class target, SEL selector) {
    return [NSString stringWithFormat:@"%p:%@", target, NSStringFromSelector(selector)];
}
static IMP haoge_settingsshelf_originalForSelector(SEL selector) {
    @synchronized (haoge_settingsshelf_guardLock) {
        return haoge_settingsshelf_guardOriginals[NSStringFromSelector(selector)].pointerValue;
    }
}

#define HAOGE_STATUS_HOOK(TYPE, NAME) \
static TYPE NAME(id self, SEL command) { \
    if (haoge_settingsshelf_repairIsEnabled()) return (TYPE)0; \
    IMP original = haoge_settingsshelf_originalForSelector(command); \
    return original ? ((TYPE (*)(id, SEL))original)(self, command) : (TYPE)0; \
}
#define HAOGE_VALID_HOOK(TYPE, NAME) \
static TYPE NAME(id self, SEL command, id argument) { \
    if (haoge_settingsshelf_repairIsEnabled()) return (TYPE)1; \
    IMP original = haoge_settingsshelf_originalForSelector(command); \
    return original ? ((TYPE (*)(id, SEL, id))original)(self, command, argument) : (TYPE)0; \
}
HAOGE_STATUS_HOOK(signed char, haoge_settingsshelf_status_c)
HAOGE_STATUS_HOOK(unsigned char, haoge_settingsshelf_status_C)
HAOGE_STATUS_HOOK(short, haoge_settingsshelf_status_s)
HAOGE_STATUS_HOOK(unsigned short, haoge_settingsshelf_status_S)
HAOGE_STATUS_HOOK(int, haoge_settingsshelf_status_i)
HAOGE_STATUS_HOOK(unsigned int, haoge_settingsshelf_status_I)
HAOGE_STATUS_HOOK(long, haoge_settingsshelf_status_l)
HAOGE_STATUS_HOOK(unsigned long, haoge_settingsshelf_status_L)
HAOGE_STATUS_HOOK(long long, haoge_settingsshelf_status_q)
HAOGE_STATUS_HOOK(unsigned long long, haoge_settingsshelf_status_Q)
HAOGE_STATUS_HOOK(bool, haoge_settingsshelf_status_B)
HAOGE_VALID_HOOK(signed char, haoge_settingsshelf_valid_c)
HAOGE_VALID_HOOK(unsigned char, haoge_settingsshelf_valid_C)
HAOGE_VALID_HOOK(short, haoge_settingsshelf_valid_s)
HAOGE_VALID_HOOK(unsigned short, haoge_settingsshelf_valid_S)
HAOGE_VALID_HOOK(int, haoge_settingsshelf_valid_i)
HAOGE_VALID_HOOK(unsigned int, haoge_settingsshelf_valid_I)
HAOGE_VALID_HOOK(long, haoge_settingsshelf_valid_l)
HAOGE_VALID_HOOK(unsigned long, haoge_settingsshelf_valid_L)
HAOGE_VALID_HOOK(long long, haoge_settingsshelf_valid_q)
HAOGE_VALID_HOOK(unsigned long long, haoge_settingsshelf_valid_Q)
HAOGE_VALID_HOOK(bool, haoge_settingsshelf_valid_B)
#undef HAOGE_STATUS_HOOK
#undef HAOGE_VALID_HOOK

static IMP haoge_settingsshelf_statusReplacement(char code) {
    switch (code) {
        case 'c': return (IMP)haoge_settingsshelf_status_c;
        case 'C': return (IMP)haoge_settingsshelf_status_C;
        case 's': return (IMP)haoge_settingsshelf_status_s;
        case 'S': return (IMP)haoge_settingsshelf_status_S;
        case 'i': return (IMP)haoge_settingsshelf_status_i;
        case 'I': return (IMP)haoge_settingsshelf_status_I;
        case 'l': return (IMP)haoge_settingsshelf_status_l;
        case 'L': return (IMP)haoge_settingsshelf_status_L;
        case 'q': return (IMP)haoge_settingsshelf_status_q;
        case 'Q': return (IMP)haoge_settingsshelf_status_Q;
        case 'B': return (IMP)haoge_settingsshelf_status_B;
        default: return NULL;
    }
}
static IMP haoge_settingsshelf_validReplacement(char code) {
    switch (code) {
        case 'c': return (IMP)haoge_settingsshelf_valid_c;
        case 'C': return (IMP)haoge_settingsshelf_valid_C;
        case 's': return (IMP)haoge_settingsshelf_valid_s;
        case 'S': return (IMP)haoge_settingsshelf_valid_S;
        case 'i': return (IMP)haoge_settingsshelf_valid_i;
        case 'I': return (IMP)haoge_settingsshelf_valid_I;
        case 'l': return (IMP)haoge_settingsshelf_valid_l;
        case 'L': return (IMP)haoge_settingsshelf_valid_L;
        case 'q': return (IMP)haoge_settingsshelf_valid_q;
        case 'Q': return (IMP)haoge_settingsshelf_valid_Q;
        case 'B': return (IMP)haoge_settingsshelf_valid_B;
        default: return NULL;
    }
}

static id haoge_settingsshelf_suggestionHook(id self, SEL command, id argument) {
    if (haoge_settingsshelf_repairIsEnabled()) return nil;
    IMP original = haoge_settingsshelf_originalForSelector(command);
    return original ? ((id (*)(id, SEL, id))original)(self, command, argument) : nil;
}
static id haoge_settingsshelf_healthSpecifiersHook(id self, SEL command) {
    if (haoge_settingsshelf_repairIsEnabled()) return nil;
    IMP original = haoge_settingsshelf_originalForSelector(command);
    return original ? ((id (*)(id, SEL))original)(self, command) : nil;
}

static void haoge_settingsshelf_addItemHook(id self, SEL command, id item) {
    if (haoge_settingsshelf_repairIsEnabled() && haoge_settingsshelf_addItemMatches(item)) return;
    IMP original = haoge_settingsshelf_originalForSelector(command);
    if (original) ((void (*)(id, SEL, id))original)(self, command, item);
}

static BOOL haoge_settingsshelf_signatureMatches(Method method, unsigned int arguments,
                                                   char returnCode, const char *arg2Code) {
    if (!method || method_getNumberOfArguments(method) != arguments ||
        haoge_settingsshelf_returnCode(method) != returnCode) return NO;
    if (arg2Code && (arguments < 3 || haoge_settingsshelf_argumentCode(method, 2) != *arg2Code)) return NO;
    return YES;
}
static BOOL haoge_settingsshelf_installMethod(Class target, SEL selector, IMP replacement,
                                               unsigned int arguments, char expectedReturn,
                                               const char *arg2Type) {
    if (!target || !selector || !replacement) return NO;
    NSString *key = haoge_settingsshelf_installKey(target, selector);
    @synchronized (haoge_settingsshelf_guardLock) {
        if ([haoge_settingsshelf_guardInstalled containsObject:key]) return YES;
        Method method = class_getInstanceMethod(target, selector);
        if (!haoge_settingsshelf_signatureMatches(method, arguments, expectedReturn, arg2Type)) return NO;
        IMP prior = method_getImplementation(method), original = NULL;
        MSHookMessageEx(target, selector, replacement, &original);
        if (!original) original = prior;
        if (!original) return NO;
        haoge_settingsshelf_guardOriginals[NSStringFromSelector(selector)] = [NSValue valueWithPointer:original];
        [haoge_settingsshelf_guardInstalled addObject:key];
        return YES;
    }
}

void haoge_settingsshelf_installGuards(void) {
    // Called by the parent runtime after preference notifications, activation,
    // and bundle loads. Refresh every time; hook installation itself is idempotent.
    BOOL repair = haoge_settingsshelf_preferenceBool(@"suppressBatteryServiceWarnings");
    BOOL update = haoge_settingsshelf_preferenceBool(@"suppressSoftwareUpdatePrompt");
    atomic_store_explicit(&haoge_settingsshelf_repairEnabled, repair, memory_order_relaxed);
    atomic_store_explicit(&haoge_settingsshelf_updateEnabled, update, memory_order_relaxed);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        haoge_settingsshelf_guardLock = [NSObject new];
        haoge_settingsshelf_guardInstalled = [NSMutableSet set];
        haoge_settingsshelf_guardOriginals = [NSMutableDictionary dictionary];
    });
    @synchronized (haoge_settingsshelf_guardLock) {
        Class battery = NSClassFromString(@"BatteryUIResourceClass");
        Class batteryMeta = battery ? object_getClass(battery) : Nil;
        for (NSString *name in @[@"genuineBatteryStatus", @"getBatteryHealthServiceState"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = batteryMeta ? class_getInstanceMethod(batteryMeta, selector) : NULL;
            char result = method ? haoge_settingsshelf_returnCode(method) : '\0';
            IMP replacement = haoge_settingsshelf_statusReplacement(result);
            haoge_settingsshelf_installMethod(batteryMeta, selector, replacement, 2, result, NULL);
        }
        // BatteryUsageUI's observed ABI is +getBatteryServiceSuggestion
        // (@16@0:8), without an explicit argument. Keep the older spelling
        // separate: installing its three-argument IMP here would be unsafe.
        SEL suggestion = NSSelectorFromString(@"getBatteryServiceSuggestion");
        haoge_settingsshelf_installMethod(batteryMeta, suggestion, (IMP)haoge_settingsshelf_healthSpecifiersHook,
                                          2, '@', NULL);
        SEL legacySuggestion = NSSelectorFromString(@"getBatteryServiceSuggestion:");
        haoge_settingsshelf_installMethod(batteryMeta, legacySuggestion, (IMP)haoge_settingsshelf_suggestionHook,
                                          3, '@', "@");

        Class health = NSClassFromString(@"SystemHealthUI");
        SEL healthSpecs = NSSelectorFromString(@"getCurrentSystemHealthInfoSpecifiers");
        haoge_settingsshelf_installMethod(health, healthSpecs, (IMP)haoge_settingsshelf_healthSpecifiersHook,
                                          2, '@', NULL);
        for (NSString *name in @[@"isVaildCAA:", @"isValidCAA:"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = health ? class_getInstanceMethod(health, selector) : NULL;
            char result = method ? haoge_settingsshelf_returnCode(method) : '\0';
            IMP replacement = haoge_settingsshelf_validReplacement(result);
            haoge_settingsshelf_installMethod(health, selector, replacement, 3, result, "@");
        }

        Class group = NSClassFromString(@"FLGroupViewModelImpl");
        SEL addItem = NSSelectorFromString(@"addItem:");
        haoge_settingsshelf_installMethod(group, addItem, (IMP)haoge_settingsshelf_addItemHook,
                                          3, 'v', "@");
    }
}
