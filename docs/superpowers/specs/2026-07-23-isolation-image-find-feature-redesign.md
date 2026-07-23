# `find(image=...)` 图片查找重构设计：特征点 + 模板精修

> 状态：已实现  
> 日期：2026-07-23

---

## 一、背景与问题

现有 `find(image=...)` 基于 OpenCV 的 `TM_CCOEFF_NORMED` 多尺度模板匹配，在以下场景命中率偏低或体验不佳：

1. **多机尺寸差异**：不同分辨率/DPI 手机上，同一按钮渲染大小不同，固定缩放范围 0.8~1.2 覆盖不足。
2. **界面轻微变化**：颜色主题、阴影、弹窗遮罩等微变会导致全局像素相似度下降。
3. **全屏大图搜索慢**：在全屏高分辨率截图上做逐像素模板匹配，耗时长且容易错过小目标。
4. **屏幕录制权限经常缺失**：当前只在宏启动前主动申请一次，执行中若权限被撤销或未授予，`find` 直接失败。

本方案引入**特征点粗定位 + 模板匹配精修**的混合策略，并补齐执行中主动申请屏幕录制权限的能力。

---

## 二、目标

- 提升 `find(image=...)` 在不同分辨率、轻微 UI 变化、全屏大图场景下的命中率。
- 保持对纯色/低纹理目标的可用性（fallback 到传统模板匹配）。
- 在宏执行过程中遇到屏幕录制权限缺失时，主动弹出授权并自动恢复执行。
- 不显著增加包体积（继续使用 OpenCV 内置 ORB/AKAZE）。

---

## 三、DSL 语法

### 3.1 基本用法（默认 ORB）

```dsl
find(image="button_login.jpg") {
    click()
}
```

### 3.2 完整参数

```dsl
find(
    image="button_login.jpg",
    feature="orb",         # "orb" | "akaze" | "template"
    threshold=0.80,        # 最终模板精修相似度阈值
    minMatches=6,          # 特征点匹配最少内点数
    region=[100, 200, 900, 1200]
) {
    click()
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `image` | string | 是 | 模板图片文件名，存于插件 assets 目录 |
| `feature` | string | 否 | 粗定位算法，默认 `"orb"` |
| `threshold` | float | 否 | 模板精修阈值 0.0~1.0，默认 `0.80` |
| `minMatches` | int | 否 | 特征点几何校验通过的最少内点数，默认 `6` |
| `region` | list[int] | 否 | 搜索区域 `[left, top, right, bottom]` |

### 3.3 与现有 `find` 的关系

`find` 内部优先级不变：

1. 若存在 `image`，走图片匹配（本方案）。
2. 否则若存在 `color`，走颜色匹配。
3. 否则若存在 `target`，走 Accessibility 节点匹配。

---

## 四、算法流程

```
加载模板图 -> 缩放到最长边 <= 320px ->

确保屏幕录制权限（若缺失则主动申请）->
获取最新屏幕帧 ->

若 feature != "template":
    对模板图提取关键点与描述子（ORB/AKAZE）
    对屏幕帧（或 region 裁剪后、降采样后）提取关键点与描述子
    BFMatcher + KNN + ratio test 初步匹配
    RANSAC / 单应性矩阵剔除误匹配
    若有效内点数 >= minMatches:
        估算模板在屏幕上的候选矩形与估计缩放
        在该候选区域内执行多尺度模板匹配精修
        若 score >= threshold: 命中，返回中心坐标

若 feature == "template" 或特征点流程未命中:
    在 screen/region 内执行传统多尺度模板匹配（放宽 scale 0.5~2.0）
    若 score >= threshold: 命中

未命中 -> postStatus "find: 未找到图片" -> 不执行子块
```

---

## 五、模块设计

### 5.1 `FeatureMatcher`（新增）

职责：特征点检测、描述、匹配、几何校验。

核心方法：

```kotlin
object FeatureMatcher {
    fun match(
        template: Mat,
        screen: Mat,
        algorithm: String = "orb",
        minMatches: Int = 6,
        region: Rect? = null
    ): FeatureMatchResult?
}

data class FeatureMatchResult(
    val rect: Rect,      // 候选区域（屏幕坐标）
    val estimatedScale: Double
)
```

实现要点：

- 支持 `ORB` 与 `AKAZE`。
- `ORB` 默认最多 500 个关键点，`AKAZE` 默认最多 300 个。
- 屏幕帧高度 > 1080 时先等比降采样到 1080p，匹配结果再映射回原坐标。
- 若指定 `region`，先裁剪屏幕到该区域再提取特征。
- 使用 BFMatcher + KNN（k=2）+ Lowe's ratio test（0.75）。
- 使用 `Calib3d.findHomography` + RANSAC 做几何校验。

### 5.2 `TemplateMatcher`（新增，从 `ImageFinder` 抽取）

职责：纯多尺度模板匹配，可限定搜索区域和缩放范围。

核心方法：

```kotlin
object TemplateMatcher {
    fun match(
        template: Mat,
        screen: Mat,
        searchRect: Rect? = null,
        minScale: Double = 0.5,
        maxScale: Double = 2.0,
        scaleStep: Double = 0.05,
        useBlur: Boolean = true
    ): MatchResult
}
```

实现要点：

- 从现有 `ImageFinder.matchMultiScale` 抽取并简化。
- 支持灰度匹配；颜色匹配作为可选项保留但默认关闭。
- 在候选区域内匹配时，使用更小步长（如 0.02）和更窄范围以提高精度。

### 5.3 `ImageFinder`（重构为编排器）

职责：加载模板、选择策略、调用 `FeatureMatcher` 或 `TemplateMatcher`、管理 fallback 与资源释放。

```kotlin
object ImageFinder {
    fun find(
        context: Context,
        assetsDir: String?,
        imageName: String,
        threshold: Double = 0.80,
        region: List<*>? = null,
        options: Map<String, Any>? = null
    ): Point?
}
```

`options` 新增字段：

- `feature`: `"orb"` | `"akaze"` | `"template"`
- `minMatches`: Int
- `useColor`, `useBlur`, `minScale`, `maxScale`, `scaleStep` 仍保留供模板匹配使用。

### 5.4 `ScreenCapturePermissionRequester`（新增）

职责：在宏执行过程中阻塞式申请屏幕录制权限，并等待结果。

```kotlin
object ScreenCapturePermissionRequester {
    fun request(context: Context, timeoutMs: Long = 30000): Boolean
    fun onResult(granted: Boolean)
}
```

流程：

1. `MacroExecutor` 调用 `request(context)`。
2. `request` 重置 `CountDownLatch`，并启动 `MainActivity`（action = `ACTION_REQUEST_SCREEN_CAPTURE`）。
3. `MainActivity` 弹出系统授权对话框。
4. `onActivityResult` 调用 `ScreenCaptureHelper.onActivityResult` 初始化，并调用 `ScreenCapturePermissionRequester.onResult(granted)`。
5. `request` 等待 latch 释放或超时，返回结果。

### 5.5 `MacroExecutor`（调整）

- 在 `executeFindStep` 的 `image` 分支与 `color` 分支前调用 `ensureScreenCapturePermission()`。
- 解析 `feature`、`minMatches` 并透传给 `ImageFinder`。

```kotlin
private fun ensureScreenCapturePermission(): Boolean {
    if (ScreenCaptureHelper.isGranted(service)) return true
    postStatus("find: 需要屏幕录制权限")
    val granted = ScreenCapturePermissionRequester.request(service)
    if (!granted) postStatus("find: 未获得屏幕录制权限")
    return granted
}
```

### 5.6 `MainActivity`（调整）

- 在 `onCreate` 与 `onNewIntent` 中识别 `ACTION_REQUEST_SCREEN_CAPTURE`。
- 识别到后调用 `ScreenCaptureHelper.requestPermission(this, REQUEST_SCREEN_CAPTURE)`。
- `onActivityResult` 中除通知 Flutter `pendingResult` 外，同时调用 `ScreenCapturePermissionRequester.onResult(granted)`。

---

## 六、性能与资源控制

1. **屏幕降采样**：屏幕高度 > 1080 时先降到 1080p 做特征点检测，结果映射回原坐标。
2. **模板尺寸限制**：最长边不超过 320px（沿用现有图片裁剪逻辑）。
3. **搜索区域优先**：若用户指定 `region`，只在区域内提取特征和精修。
4. **关键点上限**：ORB 500、AKAZE 300，防止内存抖动。
5. **单次匹配超时**：`find` 整体设置 5 秒上限，超时返回未命中并 postStatus。
6. **资源释放**：所有 `Mat` 在 `try/finally` 中释放，`FeatureMatcher` 与 `TemplateMatcher` 不长期持有资源。

---

## 七、错误与边界处理

| 场景 | 处理 |
|------|------|
| 模板文件不存在 | postStatus "find: 图片加载失败"，返回未命中 |
| 屏幕权限未授予 | 主动申请；denied/超时则 postStatus 并跳过 |
| 特征点不足 | 自动 fallback 到传统模板匹配 |
| RANSAC 内点不足 | fallback 到传统模板匹配 |
| 精修区域越界 | 裁剪到屏幕有效范围内 |
| 纯色/低纹理按钮 | 依赖 fallback 模板匹配 |
| 单次匹配超时 | postStatus "find: 匹配超时"，返回未命中 |

---

## 八、文件改动清单

| 文件 | 改动说明 |
|------|----------|
| `android/app/src/main/kotlin/com/example/isolation/FeatureMatcher.kt` | 新增：ORB/AKAZE 特征点检测与几何校验 |
| `android/app/src/main/kotlin/com/example/isolation/TemplateMatcher.kt` | 新增：多尺度模板匹配（从 ImageFinder 抽取） |
| `android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt` | 重构：策略编排、fallback、资源释放 |
| `android/app/src/main/kotlin/com/example/isolation/ScreenCapturePermissionRequester.kt` | 新增：执行中申请屏幕录制权限 |
| `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt` | 调整：解析 feature/minMatches，find 前确保权限 |
| `android/app/src/main/kotlin/com/example/isolation/MainActivity.kt` | 调整：处理 ACTION_REQUEST_SCREEN_CAPTURE，通知 requester |
| `lib/services/macro_program_parser.dart` | 调整：解析 `feature`、`minMatches` 参数 |
| `lib/services/native_channel.dart` | 若需要，新增权限状态查询（已有） |
| `lib/screens/instruction_manual_screen.dart` | 更新：文档说明新参数与行为 |

---

## 九、测试策略

1. **单元测试（如果有固定截图素材）**
   - 同一张模板在不同分辨率截图上的命中。
   - 主题色变化后的命中。
   - 纯色按钮的 fallback 命中。
   - region 限定后的正确性。

2. **真机测试**
   - 1080p / 2K 手机各一台。
   - 弹窗/遮罩场景。
   - 手动撤销权限后，执行中自动申请流程。

3. **边界测试**
   - 模板图包含大量背景 vs 精确裁剪。
   - 超大全屏图搜索速度。
   - 连续多个 `find` 步骤时权限只申请一次。

---

## 十、待后续决策

1. `feature` 默认用 `orb` 还是 `akaze`？`akaze` 对缩放更鲁棒但稍慢，可先默认 `orb`，后续根据真机数据调整。
2. 是否暴露 `maxKeypoints`、`ratioTest` 等高级参数给 DSL？第一阶段不暴露，保持简洁。
3. 命中后是否需要在悬浮球显示匹配到的矩形区域？可作为后续可视化增强。
