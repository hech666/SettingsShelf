# SettingsShelf / 插件收纳

独立 iOS 设置收纳插件，包标识 `com.haoge.settingsshelf`。仅注入 `com.apple.Preferences`；最低 iOS 15.0，主要待测环境为 iOS 16 / Roothide。**安装后默认生效，没有启用开关；旧版保存的 enabled 值不再读取。**设置首页只保留两个分类入口：

- **越狱插件**：使用用户提供的 `系统插件.png`。
- **应用软件**：使用用户提供的 `应用软件.png`。

两张图均缩至 **60×60 像素的 RGBA PNG**，保留透明边缘、移除图片附带元数据，并采用 PNG 压缩。以 `@2x` 资源在设置列表中按 30×30 pt 显示。

## 真正收纳与修复

- 将识别出的越狱插件设置、第三方应用设置从首页移入两个分类，系统设置仍在原位。
- 越狱插件列表移植原 TweaksHub 的 PreferenceLoader 流程：递归枚举 `/Library/PreferenceLoader/Preferences` 的 plist，检查外层 `filter`／`pl_filter` 与 entry 的 `pl_filter` CoreFoundation 版本范围，优先有效 `bundlePath`，否则查找越狱与系统 PreferenceBundles；只剔除插件自身。
- 将原始 entry 交给系统 Preferences 的真实 `SpecifiersFromPlist`，使用已核实的九参数 ABI：`input(items:[entry]), nil, 当前分类控制器, filename, NSBundle, nil, nil, 当前分类控制器, NSMutableArray *__strong *`。不改写第三方 target class／cellClass，保留 lazy-bundle，缺失 identifier 按原 label／文件名回退，缺失 name 使用文件名，最终按名称本地化不区分大小写排序并去重。
- 越狱插件分类不再依赖首页偶尔返回的部分列表；冷启动即可独立生成完整可发现的插件清单。完整扫描后允许新增、卸载与过滤变化更新；枚举或生成失败时不提交半成品。旧行只能回退给生成它的同一有效弱控制器，跨控制器失败返回空列表，避免已销毁 target；不持有控制器，不引入循环引用。
- 应用软件仍沿用原始首页 PSSpecifier、target、图标及跳转信息。同一个根控制器内合并实际观察到的第三方应用行，系统行只取当前快照；应用列表的部分返回不作为卸载证明。分类页通过主线程通知合并刷新，同 ID 的新对象仍会更新。
- 仅 Hook 设置根控制器；初始化列表时才修改数组，已加载页面通过 Preferences 原生连续移除／插入 API 更新，不对活表调用 `setSpecifiers:` 或 `reloadData`。
- 分类导航组固定放在 Apple ID／头像账户组下方、飞行模式／Wi-Fi 网络组上方；完整移动三项导航，兼容系统延迟插入及重复整理。
- 不提供插件自身的独立设置项；两个分类入口及“越狱插件”内的附加功能保持可用。
- “越狱插件”分类下直接提供“附加功能”：屏蔽部件与维修记录、屏蔽系统更新提示、自定义名称与图标。两个屏蔽项独立、默认关闭；收纳仍始终启用。
- 自定义仅对越狱插件入口和“越狱插件”分类生效；应用软件及其分类不展示自定义项，忽略旧应用映射，不删除用户存储。保留原 identifier、target、深链及 lazy-bundle；使用自家偏好域，不改写第三方 plist。
- 自定义图标按原图标的 point 尺寸重绘，保留透明度、图片比例及 GIF 帧；无原始图标时使用 30×30 pt。
- 不包含原 TweaksHub 二进制；新增功能依据静态证据独立实现，不声称逐字节还原原版。
- 与 TweaksHub、Shuffle 等同类设置重排插件声明冲突。

## 附加功能范围

- 维修屏蔽限定设置进程内的维修／电池提示展示；仅对实际存在且 ABI 匹配的私有接口安装钩子。未修改硬件数据，也不改变系统诊断结果。
- 更新屏蔽针对设置首页的更新提示行及仅包含提示的分组，不禁用 OTA 服务或更新下载。
- 自定义图标从用户选定文件或目录导入自家目录，支持 PNG/JPG/JPEG/GIF 与倍率后缀；恢复默认会删除显式名称和图标映射，重新显示原始入口名称与图标。


## GitHub 云编译

公共仓库：`hech666/SettingsShelf`。工作流在推送 main 或手动触发时执行：

1. 校验名称、plist、两个 PNG 的 60×60 尺寸、源码引用、原版库存生成 ABI 与同所有者失败回退；执行 Foundation 库存测试（含冷启动、重复打开、过滤、损坏 plist、生成失败、弱控制器销毁），保留全部分组、顶部插入、附加功能及自定义范围回归。
2. 使用 macOS 15、Xcode、Theos 与 iPhoneOS 16.5 SDK 构建；默认 scheme 为 Roothide。
3. 包版本使用 `5.2.0-${{ github.run_number }}`。
4. 主插件和 PreferenceBundle 均仅编译 **arm64e 单架构**；验包拒绝 arm64 和 FAT 通用二进制，并验证签名代码页、过滤器与包内图标，生成源文件哈希清单。
5. 验证成功后上传 Artifact 并发布 Release。

安装包、PackageVerification.json 和 SourceManifest.json 随云构建上传。实际是否构建成功以对应 run 结果为准；编译/验签通过不代表已真机测试。

## 本地 Theos 构建

```sh
sh build.sh roothide
# 或使用常规 rootless Theos
sh build.sh rootless
```

工程 SDK 固定 16.5、架构仅 arm64e（适配 iPhone 14 Pro Max 等 arm64e 系统设置进程）。移除 arm64 仅减少体积，不改变功能；旧 arm64 设备不再适用。RootHide 使用官方 `jbroot()` API；不扫描随机根作为配置写入路径。

## 验证说明

`Validation/project_check.py` 是纯标准库静态检查；`Validation/verify_package.py` 检查真实 deb 的架构、CodeDirectory 哈希和图标。历史的 `Validation/Verification.json` 只描述早期本机对象编译，不能当本次云构建结果。尚未安装/注入或执行真机功能测试。

## 主要源码

- `Hooks/HaogeSettingsShelfMain.xm`：加载收纳运行时。
- `Sources/HaogeSettingsShelfRuntime.m`：动态 Hook、保留真实数组、兼容延迟插入、分类导航和前台刷新。
- `Sources/HaogeSettingsShelfGrouping.m`：可独立测试的分桶、重复刷新与原对象保留逻辑。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfCategoryListController.m`：两个原生设置分类页。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfCustomizationController.m`：仅越狱插件的名称／图标编辑与文件导入。
- `Sources/HaogeSettingsShelfPaths.h`：官方 scheme 资源路径。
