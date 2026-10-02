# 通知栏小图标替换设计

> 日期：2026-10-01
> 状态：待确认

## 1. 背景

用户反馈：软件在**通知栏**的通知，标题左侧显示的是一个"**圆球中间带感叹号**"的符号，希望改成自定义图标。

## 2. 现状分析

经排查，App 目前有两处通知使用了 Android 系统内置图标 `android.R.drawable.ic_menu_info_details`（即"圆圈感叹号"）：

| 位置 | 文件 | 用途 |
|:---|:---|:---|
| 1 | [FloatingBallService.kt](file:///workspace/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt#L359) 的 `startForegroundNotification()` | 悬浮球前台服务常驻通知 |
| 2 | [MacroStatusNotifier.kt](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroStatusNotifier.kt#L177) 的 `post()` | 通知栏状态通知（运行状态 + print 输出） |

系统图标的问题：

- 无品牌辨识度，所有用该图标的 App 长得一模一样；
- 部分 ROM（小米 / 华为 / OPPO 等）会对系统图标做二次着色或裁剪，效果不可控。

## 3. 目标

- 两处通知的小图标统一替换为 **Isolation 自定义图标**；
- 图标风格与现有应用图标（两个嵌套圆角矩形线框）呼应；
- 兼容 Android 5.0（API 21）~ 15，无锯齿、无白底。

## 4. 技术要点

### 4.1 Android 通知小图标（small icon）规范

- 通知小图标**只使用图片的 Alpha 通道**，系统会将其渲染为白色（浅色）或灰色（深色/系统着色），**原始颜色会被忽略**；
- 因此素材必须是：**透明背景 + 单色图形**（图形颜色随意，反正只取 Alpha）；
- 图标尺寸建议 24dp，推荐提供 `48x48 / 72x72 / 96x96` 多密度 PNG，或直接使用 **Vector Drawable（矢量 XML）**——本项目全部源码化，选矢量最合适，任意密度都清晰；
- 安全区域：图形主体放在中心约 66%（16dp/24dp）以内，四周留白，避免被部分 ROM 裁切。

### 4.2 推荐方案：Vector Drawable（首选）

- 新建 `android/app/src/main/res/drawable/ic_notification.xml`；
- 用 `path` 绘制与应用图标一致的**双圆角矩形线框**（品牌延续），线宽约 2dp；
- Vector 优点：零锯齿、任意尺寸、体积小、无需多密度文件。

### 4.3 备选方案：PNG（可选）

- 若希望使用与桌面图标完全一致的位图，可将桌面图标转为透明单色 PNG，放入 `res/drawable-nodpi/`（或 mipmap），代码里引用同一资源。

## 5. 实现步骤

1. **新增图标资源** `drawable/ic_notification.xml`（矢量，双圆角矩形线框，透明背景）；
2. **修改 [FloatingBallService.kt](file:///workspace/android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt#L359)**：
   - `.setSmallIcon(android.R.drawable.ic_menu_info_details)` → `.setSmallIcon(R.drawable.ic_notification)`
3. **修改 [MacroStatusNotifier.kt](file:///workspace/android/app/src/main/kotlin/com/example/isolation/MacroStatusNotifier.kt#L177)**：
   - `.setSmallIcon(android.R.drawable.ic_menu_info_details)` → `.setSmallIcon(R.drawable.ic_notification)`
4. **验证**：本地 `flutter build apk --debug` 或推送触发 CI 打包，安装后检查：
   - 悬浮球开启后的常驻通知图标；
   - 设置 → 开启"通知栏状态通知"后的状态通知图标；
   - 均显示为自定义线框图标（白色线框，透明底），无感叹号。

## 6. 图标内容建议（待确认）

| 选项 | 描述 |
|:---|:---|
| A（推荐） | 与应用图标一致的**双圆角矩形嵌套线框**，品牌延续 |
| B | 单圆角矩形线框，更简洁 |
| C | 用户提供设计稿 / 图片素材，按素材生成 |

> 如选择 C，请提供图片路径或描述期望的图形。
