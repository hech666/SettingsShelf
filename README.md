# SettingsShelf / 越狱插件和应用软件

独立 iOS 设置收纳插件，包标识 `com.haoge.settingsshelf`。仅注入 `com.apple.Preferences`；最低 iOS 15.0，主要待测环境为 iOS 16 / Roothide。**安装后默认生效，没有启用开关；旧版保存的 enabled 值不再读取。**设置首页只保留两个分类入口：

- **越狱插件**：使用用户提供的 `系统插件.png`。
- **应用软件**：使用用户提供的 `应用软件.png`。

两张图均缩至 **60×60 像素的 RGBA PNG**，保留透明边缘、移除图片附带元数据，并采用 PNG 压缩。以 `@2x` 资源在设置列表中按 30×30 pt 显示。

## 真正收纳与修复

- 将识别出的越狱插件设置、第三方应用设置从首页移入两个分类，系统设置仍在原位。
- 保留原始 PSSpecifier、target、图标、lazy-bundle 和跳转信息，不扫描磁盘拼造第三方设置链接。
- 同时覆盖根页面 getter/setter、首次显示、前台恢复和延迟插入第三方项目，原位修改 PSListController 实际使用的数组。
- 不再把已经加载的目标 Class 覆盖成字符串；目标页不可用时保留原行，不进行隐藏。
- 设置面板改为当前收纳计数、两个分类入口与“重新整理设置首页”，没有开关或配置写入。
- 不含原 TweaksHub 二进制，也不含屏蔽电池维修提示、屏蔽系统更新等无关功能。
- 与 TweaksHub、Shuffle 等同类设置重排插件声明冲突。

## GitHub 云编译

公共仓库：`hech666/SettingsShelf`。工作流在推送 main 或手动触发时执行：

1. 校验名称、plist、两个 PNG 的 60×60 尺寸及源码引用。
2. 使用 macOS 15、Xcode、Theos 与 iPhoneOS 16.5 SDK 构建；默认 scheme 为 Roothide。
3. 包版本使用 `5.2.0-${{ github.run_number }}`。
4. 对 arm64 / arm64e 切片分别验证签名代码页、过滤器与包内图标，生成源文件哈希清单。
5. 验证成功后上传 Artifact 并发布 Release。

安装包、PackageVerification.json 和 SourceManifest.json 随云构建上传。实际是否构建成功以对应 run 结果为准；编译/验签通过不代表已真机测试。

## 本地 Theos 构建

```sh
sh build.sh roothide
# 或使用常规 rootless Theos
sh build.sh rootless
```

工程 SDK 固定 16.5、架构 arm64 + arm64e。RootHide 使用官方 `jbroot()` API；不扫描随机根作为配置写入路径。

## 验证说明

`Validation/project_check.py` 是纯标准库静态检查；`Validation/verify_package.py` 检查真实 deb 的架构、CodeDirectory 哈希和图标。历史的 `Validation/Verification.json` 只描述早期本机对象编译，不能当本次云构建结果。尚未安装/注入或执行真机功能测试。

## 主要源码

- `Hooks/HaogeSettingsShelfMain.xm`：加载收纳运行时。
- `Sources/HaogeSettingsShelfRuntime.m`：动态 Hook、保留真实数组、兼容延迟插入、分类导航和前台刷新。
- `Sources/HaogeSettingsShelfGrouping.m`：可独立测试的分桶、重复刷新与原对象保留逻辑。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfCategoryListController.m`：两个原生设置分类页。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfRootListController.m`：无开关的收纳状态面板。
- `Sources/HaogeSettingsShelfPaths.h`：官方 scheme 资源路径。
