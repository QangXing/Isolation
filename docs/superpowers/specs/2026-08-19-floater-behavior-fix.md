# 悬浮球/编程球行为修复方案

## 背景

当前启用编程球（floaterPlugin）后出现以下三类异常现象：

1. **默认悬浮球与主副球显示冲突**：启用编程球后，默认悬浮球变成空白，同时主球和副球显示出来。期望行为是启用编程球后默认悬浮球不再显示，主球和副球只在 DSL 中声明的 `location` 位置显示。
2. **主页/管理区状态不同步、重复球、闪退**：
   - 在主页启用球后，出现上述冲突。
   - 在管理区关闭球后，主球和副球没有消失。
   - 再次开启后，屏幕上出现两对主球和副球。
   - 管理区启用后点击主/副球可以正常执行宏；主页启用后点击会闪退。
   - 期望：主页和管理区的开关状态保持同步，关闭球时主/副球必须消失，重新开启时不产生重复球。
3. **宏气泡位置错误**：启用宏后，print/状态气泡显示在默认悬浮球旁边。期望气泡显示在主球旁边。

## 根因分析

### 1. 默认悬浮球未在编程球启用时隐藏

`FloatingBallService.registerFloatersInternal()` 在注册插件球时：

- 调用了 `applyFloaterConfigInternal(...)` 重新把默认悬浮球的配置刷了一遍；
- **没有调用任何隐藏默认悬浮球的逻辑**。

结果是默认球仍然挂在屏幕上，但因为后续可能被其他逻辑影响或用户感知为“空白”。

### 2. 服务停止/销毁时没有清理插件球

`FloatingBallService.onDestroy()` -> `hideFloatingBall()` 只移除了默认悬浮球：

```kotlin
private fun hideFloatingBall() {
    if (floatingView != null) {
        windowManager?.removeView(floatingView)
        floatingView = null
        floatingParams = null
    }
    hideBubble()
    hideAnimationOverlay()
}
```

插件球（`pluginBalls`）的视图没有被移除。

在管理区关闭球时，Flutter 侧会调用 `NativeChannel.unregisterFloaters()`，该函数调用 `clearAllPluginBalls()`。但如果用户同时关闭了“默认悬浮球”开关，或者服务因其他原因被系统回收，`onDestroy()` 不会清理插件球，导致：

- 关闭球后主/副球仍然残留在屏幕上；
- 再次启用时，旧服务实例的插件视图成为“孤儿视图”，新服务实例又会创建一对新的主/副球，从而出现**两对球**；
- 旧视图上的点击事件仍然绑定在已销毁服务实例的 `FloaterRegistry` 和 `pluginVariables` 上，数据与文件上下文已经失效，点击后**闪退**。

### 3. 主页与管理区开关不同步

两者最终都调用 `PluginProvider.setEnabled()`，数据层面已经同步。但 `PluginCard` 与 `_PluginListItem` 的开关表现可能因 UI 层状态产生短暂不一致。需要确保：

- 两个页面都基于同一个 `PluginProvider.enabled` 状态刷新；
- 切换时异步操作完成后统一 `notifyListeners()`。

### 4. 气泡位置基于默认悬浮球

`showBubble()` 使用 `floatingParams` 和 `ballSizePx` 计算气泡位置，这两个变量都是默认悬浮球的参数。启用编程球后默认球被隐藏，但气泡仍然按默认球位置显示。

## 修复方案

### Android 侧（Kotlin）

#### A. 注册编程球时隐藏默认悬浮球

在 `FloatingBallService.registerFloatersInternal()` 中，创建插件球之前，隐藏默认悬浮球视图（但保持服务存活）：

```kotlin
// 隐藏默认悬浮球，避免与主/副球重叠；仅移除视图，不停服务
hideDefaultFloatingBall()
```

新增方法：

```kotlin
private fun hideDefaultFloatingBall() {
    floatingView?.let {
        try {
            windowManager?.removeView(it)
        } catch (e: Exception) {
            Log.w(TAG, "隐藏默认悬浮球失败", e)
        }
    }
    floatingView = null
    floatingParams = null
}
```

> 注意：不能与 `hideFloatingBall()` 混淆，后者会停止前台服务并 `stopSelf()`。

#### B. 服务销毁/停止时统一清理插件球

1. `onDestroy()` 中在 `hideFloatingBall()` 之前调用 `clearAllPluginBalls()`；
2. `hideFloatingBall()` 内部也调用 `clearAllPluginBalls()`，作为防御性清理；
3. `clearAllPluginBalls()` 本身需要健壮：遍历 `pluginBalls` 移除视图后清空 map。

#### C. 禁用编程球时恢复默认悬浮球（如果开关开启）

当前 `unregisterFloaters()` 只清理插件球。Flutter 侧 `setEnabled(..., false)` 已经知道默认悬浮球的显示状态 `_floatingBallVisible`，因此恢复默认球的逻辑放在 Flutter 侧更合适：

```dart
if (isFloater && !enabled) {
  await NativeChannel.unregisterFloaters();
  // 如果默认悬浮球开关是开的，重新显示默认球
  if (_floatingBallVisible) {
    await _startFloatingBallIfReady();
    final config = await loadDefaultFloaterConfig();
    await NativeChannel.applyDefaultFloaterConfig(...);
  }
}
```

#### D. 气泡位置改为主球

修改 `showBubble()`：

- 找到当前启用编程球的主球（`pluginBalls` 中 `role == "main"` 且 `visible == true` 的球）。
- 如果主球存在，使用主球的 `params` 和尺寸计算气泡位置。
- 如果不存在主球，再回退到默认悬浮球位置。

建议新增方法统一获取“气泡锚点”：

```kotlin
private data class BallAnchor(
    val params: WindowManager.LayoutParams,
    val sizePx: Int
)

private fun bubbleAnchor(): BallAnchor? {
    // 优先主球
    val main = pluginBalls.values.firstOrNull { it.visible }
    if (main != null) {
        return BallAnchor(main.params, dpToPx(main.sizeDp))
    }
    // 回退默认球
    floatingParams?.let {
        return BallAnchor(it, ballSizePx)
    }
    return null
}
```

### Flutter 侧（Dart）

#### E. 禁用编程球后恢复默认悬浮球

在 `PluginProvider.setEnabled()` 的 `isFloater && !enabled` 分支中，添加默认球恢复逻辑（见 C）。

#### F. 确保开关状态同步

- `HomeScreen` 与 `ManageScreen` 都通过 `Consumer<PluginProvider>` 或 `Selector` 监听 `plugin.enabled`。
- 异步操作完成后统一调用 `notifyListeners()`，目前已满足。重点检查 `setEnabled` 在所有分支（成功/失败）都正确刷新 `_plugins` 并通知。

### 文件改动清单

| 文件 | 改动 |
| --- | --- |
| `android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt` | 新增 `hideDefaultFloatingBall()`；注册插件球时隐藏默认球；`onDestroy()`/`hideFloatingBall()` 清理插件球；`showBubble()` 改为以主球为锚点 |
| `lib/providers/plugin_provider.dart` | 禁用编程球时，若默认悬浮球开关开启则恢复显示默认球 |

## 验证方式

1. 安装 APK 后，在管理区打开“默认悬浮球”开关，确认默认球正常显示。
2. 在主页启用一个编程球插件：
   - 默认悬浮球应消失；
   - 主球和副球按 DSL 中 `locationX/locationY` 显示；
   - 点击主球可执行宏，不闪退。
3. 在管理区关闭该编程球：
   - 主球和副球立即消失；
   - 默认悬浮球恢复显示（因为默认球开关仍开启）。
4. 重复启用/关闭 3 次，确认屏幕上只有一组主/副球，无重复。
5. 启用一个含 `print` 的宏，观察气泡出现在主球旁边。
