# SettingsShelf / 越狱插件和应用软件

独立 iOS 设置分类导航插件，包标识 `com.haoge.settingsshelf`。仅注入 `com.apple.Preferences`；最低 iOS 15.0，主要待测环境为 iOS 16 / Roothide。默认关闭，在设置中开启后显示两个入口：

- **越狱插件**：使用用户提供的 `系统插件.png`。
- **应用软件**：使用用户提供的 `应用软件.png`。

两张图均缩至 **60×60 像素的 RGBA PNG**，保留透明边缘、移除图片附带元数据，并采用 PNG 压缩。以 `@2x` 资源在设置列表中按 30×30 pt 显示。

## 首版范围

- 在设置首页添加分类入口，不搬移或删除系统原有项目。
- 插件页扫描 PreferenceLoader 描述文件，构造进入原插件 PreferenceBundle 的链接。
- 应用页读取 Settings root 的 `AppBundleID` 项，兼容外部 `THAppsSpecifiers` 提供器，并补充同类 PreferenceLoader 描述文件。没有显式元数据的应用不会猜测归类。
- 配置由偏好面板原子写入，Tweak 只读取快照。关闭开关时不添加入口。
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

- `Hooks/HaogeSettingsShelfMain.xm`：根列表 Hook、独立图标、应用项目导出接口和有界重试。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfCategoryListController.m`：两个分类页。
- `HaogeSettingsShelfPrefs/HaogeSettingsShelfRootListController.m`：启用面板。
- `Sources/HaogeSettingsShelfConfig.*`：配置快照及通知刷新。
- `Sources/HaogeSettingsShelfPaths.h`：不同 scheme 的配置与资源路径。
