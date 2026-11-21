#import "HaogeSettingsShelfCustomizationController.h"
#import "../Sources/HaogeSettingsShelfPreferences.h"
#import "../Sources/HaogeSettingsShelfPaths.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>

static UIImage *haoge_settingsshelf_imagePreview(NSString *path) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0,
        (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                    (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                    (NSString *)kCGImageSourceThumbnailMaxPixelSize:@210});
    CFRelease(source);
    if (!image) return nil;
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return result;
}

@interface HaogeSettingsShelfImageGridController : UICollectionViewController <UIDocumentPickerDelegate>
@property(nonatomic, copy) NSString *haoge_settingsshelf_identifier;
@property(nonatomic, copy) void (^haoge_settingsshelf_selection)(NSString *filename);
@property(nonatomic, copy) NSArray<NSDictionary *> *haoge_settingsshelf_files;
@end

static NSArray *haoge_settingsshelf_customizationEntriesFromRuntime(void) {
    NSArray *(*provider)(void) = (NSArray *(*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_customizationEntries");
    id value = provider ? provider() : nil;
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
static NSString *haoge_settingsshelf_customName(NSString *identifier, NSString *fallback) {
    NSString *(*function)(NSString *, NSString *) = (NSString *(*)(NSString *, NSString *))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_displayName");
    return function ? function(identifier, fallback) : fallback;
}
static UIImage *haoge_settingsshelf_customImage(NSString *identifier) {
    UIImage *(*function)(NSString *) = (UIImage *(*)(NSString *))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_customIcon");
    return function ? function(identifier) : nil;
}
static void haoge_settingsshelf_invalidateImageCache(void) {
    void (*function)(void) = (void (*)(void))dlsym(RTLD_DEFAULT, "haoge_settingsshelf_invalidateCustomization");
    if (function) function();
}
static NSString *haoge_settingsshelf_iconDirectory(void) {
    static NSString *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ directory = haoge_settingsshelf_resourcePath(@"/var/mobile/Haoge/SettingsShelf"); });
    return directory;
}
static void haoge_settingsshelf_postPreferenceChange(void) {
    haoge_settingsshelf_invalidateImageCache();
    [[NSNotificationCenter defaultCenter] postNotificationName:HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:HAOGE_SETTINGSSHELF_REGROUP_NOTIFICATION object:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)HAOGE_SETTINGSSHELF_PREFERENCES_CHANGED_NOTIFICATION, NULL, NULL, true);
}
static BOOL haoge_settingsshelf_storeDictionaryValue(NSString *dictionaryKey, NSString *entryKey, id value) {
    id old = haoge_settingsshelf_preferenceValue(dictionaryKey);
    NSMutableDictionary *dictionary = [old isKindOfClass:NSDictionary.class] ? [old mutableCopy] : [NSMutableDictionary dictionary];
    if (value) dictionary[entryKey] = value; else [dictionary removeObjectForKey:entryKey];
    return haoge_settingsshelf_setPreferenceValue(dictionaryKey, dictionary);
}
static BOOL haoge_settingsshelf_isSupportedImage(NSString *path) {
    NSString *extension = path.pathExtension.lowercaseString;
    return [@[@"png", @"jpg", @"jpeg", @"gif"] containsObject:extension];
}
static BOOL haoge_settingsshelf_filenameIsReferenced(NSString *filename) {
    id values = haoge_settingsshelf_preferenceValue(@"entryIcons");
    if (![values isKindOfClass:NSDictionary.class]) return NO;
    for (id value in [values allValues]) if ([value isKindOfClass:NSString.class] && [value isEqualToString:filename]) return YES;
    return NO;
}
static void haoge_settingsshelf_removeUnreferencedIcon(NSString *filename) {
    if (!filename.length || haoge_settingsshelf_filenameIsReferenced(filename)) return;
    NSString *path = [haoge_settingsshelf_iconDirectory() stringByAppendingPathComponent:filename.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
static NSString *haoge_settingsshelf_mappedFilename(NSString *identifier) {
    id values = haoge_settingsshelf_preferenceValue(@"entryIcons");
    id filename = [values isKindOfClass:NSDictionary.class] ? values[identifier] : nil;
    return [filename isKindOfClass:NSString.class] ? filename : nil;
}
static void haoge_settingsshelf_showSaveError(UIViewController *controller) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:@"偏好设置未能同步。更改未确认保存，请重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

@implementation HaogeSettingsShelfCustomizationListController
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:@"效果预览"]];
        for (NSDictionary *entry in haoge_settingsshelf_customizationEntriesFromRuntime()) {
            NSString *identifier = entry[@"identifier"];
            NSString *fallback = entry[@"fallbackName"] ?: entry[@"name"] ?: identifier;
            if (![identifier isKindOfClass:NSString.class] || identifier.length == 0) continue;
            NSString *name = haoge_settingsshelf_customName(identifier, fallback);
            PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil
                detail:HaogeSettingsShelfCustomizationDetailController.class cell:PSLinkCell edit:nil];
            [row setProperty:identifier forKey:@"HaogeSettingsShelfCustomizationIdentifier"];
            [row setProperty:fallback forKey:@"HaogeSettingsShelfCustomizationFallbackName"];
            UIImage *icon = entry[@"iconImage"];
            if ([icon isKindOfClass:UIImage.class]) [row setProperty:icon forKey:@"iconImage"];
            [rows addObject:row];
        }
        if (rows.count == 1) {
            PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
            [empty setProperty:@"等待收纳分类加载后，可在此修改所有插件入口和分类名称、图标。" forKey:@"footerText"];
            [rows addObject:empty];
        }
        _specifiers = rows;
    }
    return _specifiers;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
}
@end

@implementation HaogeSettingsShelfCustomizationDetailController
- (NSString *)haoge_settingsshelf_identifier {
    return [self.specifier propertyForKey:@"HaogeSettingsShelfCustomizationIdentifier"];
}
- (NSString *)haoge_settingsshelf_fallbackName {
    return [self.specifier propertyForKey:@"HaogeSettingsShelfCustomizationFallbackName"] ?: self.haoge_settingsshelf_identifier;
}
- (NSString *)haoge_settingsshelf_getName:(PSSpecifier *)specifier {
    return haoge_settingsshelf_customName(self.haoge_settingsshelf_identifier, self.haoge_settingsshelf_fallbackName);
}
- (void)haoge_settingsshelf_setName:(id)value specifier:(PSSpecifier *)specifier {
    NSString *trimmed = [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    NSString *identifier = self.haoge_settingsshelf_identifier;
    NSString *fallback = self.haoge_settingsshelf_fallbackName;
    id oldValue = haoge_settingsshelf_preferenceValue(@"entryNames");
    NSString *oldName = [oldValue isKindOfClass:NSDictionary.class] ? oldValue[identifier] : nil;
    BOOL ok = haoge_settingsshelf_storeDictionaryValue(@"entryNames", identifier, trimmed.length ? trimmed : nil);
    if (!ok) {
        haoge_settingsshelf_showSaveError(self);
        [self reloadSpecifier:specifier];
        return;
    }
    haoge_settingsshelf_postPreferenceChange();
    self.title = @"名称与图标";
    if (oldName && ![oldName isEqualToString:trimmed]) [self reloadSpecifiers];
    (void)fallback;
}
- (void)haoge_settingsshelf_openImageGrid {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = CGSizeMake(92, 116);
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 10;
    layout.sectionInset = UIEdgeInsetsMake(12, 12, 18, 12);
    HaogeSettingsShelfImageGridController *grid = [[HaogeSettingsShelfImageGridController alloc] initWithCollectionViewLayout:layout];
    grid.haoge_settingsshelf_identifier = self.haoge_settingsshelf_identifier;
    __weak typeof(self) weakSelf = self;
    grid.haoge_settingsshelf_selection = ^(NSString *filename) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *oldFilename = haoge_settingsshelf_mappedFilename(self.haoge_settingsshelf_identifier);
        if (!haoge_settingsshelf_storeDictionaryValue(@"entryIcons", self.haoge_settingsshelf_identifier, filename)) {
            haoge_settingsshelf_removeUnreferencedIcon(filename);
            haoge_settingsshelf_showSaveError(self);
            return;
        }
        haoge_settingsshelf_removeUnreferencedIcon(oldFilename);
        haoge_settingsshelf_postPreferenceChange();
        [self reloadSpecifiers];
    };
    [self.navigationController pushViewController:grid animated:YES];
}
- (void)haoge_settingsshelf_resetCustomization {
    NSString *identifier = self.haoge_settingsshelf_identifier;
    NSString *oldFilename = haoge_settingsshelf_mappedFilename(identifier);
    id oldNames = haoge_settingsshelf_preferenceValue(@"entryNames");
    NSString *oldName = [oldNames isKindOfClass:NSDictionary.class] ? oldNames[identifier] : nil;
    BOOL namesOK = haoge_settingsshelf_storeDictionaryValue(@"entryNames", identifier, nil);
    BOOL iconsOK = haoge_settingsshelf_storeDictionaryValue(@"entryIcons", identifier, nil);
    if (!namesOK || !iconsOK) { haoge_settingsshelf_showSaveError(self); return; }
    haoge_settingsshelf_removeUnreferencedIcon(oldFilename);
    haoge_settingsshelf_postPreferenceChange();
    if (oldName.length) [self reloadSpecifiers];
}
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows = [NSMutableArray array];
        [rows addObject:[PSSpecifier groupSpecifierWithName:@"名称与图标"]];
        PSSpecifier *name = [PSSpecifier preferenceSpecifierNamed:@"显示名称" target:self
            set:@selector(haoge_settingsshelf_setName:specifier:) get:@selector(haoge_settingsshelf_getName:)
            detail:nil cell:PSEditTextCell edit:nil];
        [name setProperty:@"HaogeSettingsShelfDisplayName" forKey:@"key"];
        [rows addObject:name];
        PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:@"选择图标" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [choose setButtonAction:@selector(haoge_settingsshelf_openImageGrid)];
        [rows addObject:choose];
        PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"恢复默认名称与图标" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [reset setButtonAction:@selector(haoge_settingsshelf_resetCustomization)];
        [rows addObject:reset];
        PSSpecifier *preview = [PSSpecifier preferenceSpecifierNamed:@"当前图标预览" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
        UIImage *image = haoge_settingsshelf_customImage(self.haoge_settingsshelf_identifier);
        if (!image) image = [self.specifier propertyForKey:@"iconImage"];
        if ([image isKindOfClass:UIImage.class]) [preview setProperty:image forKey:@"iconImage"];
        [rows addObject:preview];
        _specifiers = rows;
    }
    return _specifiers;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = @"名称与图标";
    _specifiers = nil;
    [self reloadSpecifiers];
}
@end

@interface HaogeSettingsShelfImageCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *haoge_settingsshelf_imageView;
@property(nonatomic, strong) UILabel *haoge_settingsshelf_titleLabel;
@end
@implementation HaogeSettingsShelfImageCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _haoge_settingsshelf_imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _haoge_settingsshelf_imageView.contentMode = UIViewContentModeScaleAspectFit;
        _haoge_settingsshelf_imageView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_haoge_settingsshelf_imageView];
        _haoge_settingsshelf_titleLabel = [UILabel new];
        _haoge_settingsshelf_titleLabel.font = [UIFont systemFontOfSize:11];
        _haoge_settingsshelf_titleLabel.textAlignment = NSTextAlignmentCenter;
        _haoge_settingsshelf_titleLabel.numberOfLines = 2;
        _haoge_settingsshelf_titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_haoge_settingsshelf_titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_haoge_settingsshelf_imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_haoge_settingsshelf_imageView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_haoge_settingsshelf_imageView.widthAnchor constraintEqualToConstant:70],
            [_haoge_settingsshelf_imageView.heightAnchor constraintEqualToConstant:70],
            [_haoge_settingsshelf_titleLabel.topAnchor constraintEqualToAnchor:_haoge_settingsshelf_imageView.bottomAnchor constant:5],
            [_haoge_settingsshelf_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:3],
            [_haoge_settingsshelf_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-3],
            [_haoge_settingsshelf_titleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-4]
        ]];
        self.contentView.layer.cornerRadius = 10;
        self.contentView.layer.masksToBounds = YES;
    }
    return self;
}
@end

@implementation HaogeSettingsShelfImageGridController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择图标";
    self.collectionView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.collectionView registerClass:HaogeSettingsShelfImageCell.class forCellWithReuseIdentifier:@"HaogeSettingsShelfImageCell"];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"扫描目录" style:UIBarButtonItemStylePlain target:self action:@selector(haoge_settingsshelf_scanFolder)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *import = [[UIBarButtonItem alloc] initWithTitle:@"导入图片文件" style:UIBarButtonItemStylePlain target:self action:@selector(haoge_settingsshelf_importFile)];
    self.toolbarItems = @[flex, import, flex];
    [self.navigationController setToolbarHidden:NO animated:NO];
    [self haoge_settingsshelf_scanDirectories];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
}
- (void)haoge_settingsshelf_scanDirectories {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    @autoreleasepool {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *roots = [NSMutableArray arrayWithObject:haoge_settingsshelf_iconDirectory()];
    NSString *home = NSHomeDirectory();
    for (NSString *base in @[home, @"/var/mobile"]) {
        for (NSString *leaf in @[@"Documents", @"Downloads"]) {
            NSString *path = [base stringByAppendingPathComponent:leaf];
            if (![roots containsObject:path]) [roots addObject:path];
        }
    }
    NSString *mediaDownloads = @"/var/mobile/Media/Downloads";
    if (![roots containsObject:mediaDownloads]) [roots addObject:mediaDownloads];
    NSMutableDictionary<NSString *, NSDictionary *> *best = [NSMutableDictionary dictionary];
    for (NSString *root in roots) {
        BOOL directory = NO;
        if (![fm fileExistsAtPath:root isDirectory:&directory] || !directory) continue;
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
        NSUInteger visited = 0;
        for (NSString *relative in enumerator) {
            if (++visited > 1800) break;
            NSString *path = [root stringByAppendingPathComponent:relative];
            BOOL isDirectory = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory || !haoge_settingsshelf_isSupportedImage(path)) continue;
            NSString *stem = path.lastPathComponent.stringByDeletingPathExtension;
            NSString *lower = stem.lowercaseString;
            NSInteger scaleRank = 0;
            if ([lower hasSuffix:@"@3x"]) { stem = [stem substringToIndex:stem.length - 3]; scaleRank = 3; }
            else if ([lower hasSuffix:@"@2x"]) { stem = [stem substringToIndex:stem.length - 3]; scaleRank = 2; }
            NSString *key = [[path.stringByDeletingLastPathComponent stringByAppendingFormat:@"/%@", stem.lowercaseString] stringByStandardizingPath];
            NSDictionary *candidate = @{@"path":path, @"title":path.lastPathComponent, @"rank":@(scaleRank)};
            NSDictionary *prior = best[key];
            if (!prior || [candidate[@"rank"] integerValue] > [prior[@"rank"] integerValue]) best[key] = candidate;
        }
    }
    NSArray *files = [[best allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"title"] localizedCaseInsensitiveCompare:b[@"title"]];
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.haoge_settingsshelf_files = files;
        [self.collectionView reloadData];
    });
    }
    });
}
- (void)haoge_settingsshelf_scanFolder {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)haoge_settingsshelf_importFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    BOOL isDirectory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory];
    if (isDirectory) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSUInteger imported = 0, visited = 0;
        unsigned long long importedBytes = 0;
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:url includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
            options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(__unused NSURL *itemURL, __unused NSError *error) { return YES; }];
        for (NSURL *itemURL in enumerator) {
            if (++visited > 5000 || imported >= 300) break;
            if (!haoge_settingsshelf_isSupportedImage(itemURL.path)) continue;
            NSNumber *regular = nil, *size = nil;
            [itemURL getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
            [itemURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            if (![regular boolValue] || size.unsignedLongLongValue > 40ULL * 1024ULL * 1024ULL) continue;
            if (importedBytes + size.unsignedLongLongValue > 64ULL * 1024ULL * 1024ULL) continue;
            if (!haoge_settingsshelf_imagePreview(itemURL.path)) continue;
            if ([self haoge_settingsshelf_copyImageAtPath:itemURL.path]) {
                ++imported;
                importedBytes += size.unsignedLongLongValue;
            }
        }
        if (accessed) [url stopAccessingSecurityScopedResource];
        [self haoge_settingsshelf_scanDirectories];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"目录扫描完成"
            message:[NSString stringWithFormat:@"已加入 %lu 张图片。", (unsigned long)imported] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!haoge_settingsshelf_isSupportedImage(url.path)) { if (accessed) [url stopAccessingSecurityScopedResource]; return; }
    NSString *filename = [self haoge_settingsshelf_copyImageAtPath:url.path];
    if (accessed) [url stopAccessingSecurityScopedResource];
    if (filename) { if (self.haoge_settingsshelf_selection) self.haoge_settingsshelf_selection(filename); [self.navigationController popViewControllerAnimated:YES]; }
}
- (NSString *)haoge_settingsshelf_copyImageAtPath:(NSString *)source {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm attributesOfItemAtPath:source error:nil];
    if (!haoge_settingsshelf_isSupportedImage(source) ||
        [attributes[NSFileSize] unsignedLongLongValue] > 40ULL * 1024ULL * 1024ULL ||
        !haoge_settingsshelf_imagePreview(source)) return nil;
    NSString *directory = haoge_settingsshelf_iconDirectory();
    NSError *error = nil;
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"[SettingsShelf] icon directory error: %@", error.localizedDescription); return nil;
    }
    NSString *extension = source.pathExtension.lowercaseString;
    NSString *filename = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:extension];
    NSString *destination = [directory stringByAppendingPathComponent:filename];
    if ([source.stringByStandardizingPath isEqualToString:destination.stringByStandardizingPath]) return source.lastPathComponent;
    if (![fm copyItemAtPath:source toPath:destination error:&error]) {
        NSLog(@"[SettingsShelf] icon copy error: %@", error.localizedDescription); return nil;
    }
    return filename;
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return self.haoge_settingsshelf_files.count; }
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    HaogeSettingsShelfImageCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"HaogeSettingsShelfImageCell" forIndexPath:indexPath];
    NSDictionary *entry = self.haoge_settingsshelf_files[indexPath.item];
    cell.haoge_settingsshelf_imageView.image = haoge_settingsshelf_imagePreview(entry[@"path"]);
    cell.haoge_settingsshelf_titleLabel.text = entry[@"title"];
    return cell;
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSString *source = self.haoge_settingsshelf_files[indexPath.item][@"path"];
    NSString *filename = [self haoge_settingsshelf_copyImageAtPath:source];
    if (!filename) return;
    if (self.haoge_settingsshelf_selection) self.haoge_settingsshelf_selection(filename);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
