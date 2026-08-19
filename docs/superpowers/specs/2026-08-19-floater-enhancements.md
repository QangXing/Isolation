# 编程球闪退修复与功能增强方案

## 需求概述

本次需要完成以下 4 项改动：

1. **修复新建编程球点击闪退**：新建编程球后，点击主球/副球会崩溃；默认悬浮球无此问题。
2. **编程球编辑器增加全屏编辑功能**：与编程宏编辑器一致，支持打开 `ProfessionalEditorScreen` 全屏编辑器。
3. **调整新建编程球默认模板**：
   - 主球单击：切换副球的显示/隐藏；
   - 副球单击：执行已启用的宏；
   - 其余默认事件（主球双击打开应用、三击停止宏、长按打印）保持原模板不变。
4. **宏/编程球设置页增加卡片置顶**：
   - 在宏设置页、编程球设置页增加“置顶卡片”开关；
   - 主页/管理区等列表按置顶状态排序：置顶项按置顶时间倒序（新的在上），未置顶项保持原有顺序；
   - 置顶卡片背景色加深。

## 根因分析

### 新建编程球点击闪退

`FloatingBallService.dispatchPluginBallEvent()` 当前把事件处理放到后台线程执行：

```kotlin
Thread {
    executeFloaterSteps(handler.children)
}.start()
```

但事件处理中包含大量必须在主线程执行的逻辑：

- `print` -> `showBubble()` 调用 `windowManager.addView`；
- `launch` -> `startActivity`；
- `launch_macro` -> `runEnabledMacro()` 内部调用 `Toast.makeText(...).show()` 与 `InputAccessibilityService.executeMacro(...)`。

默认悬浮球的单击走的是 `onBallSingleClick()`，直接在主线程调用 `runEnabledMacro()`，因此不闪退；而编程球的事件被切到后台线程，导致 UI 操作崩溃。

**修复**：事件分发改为主线程执行：

```kotlin
mainHandler.post {
    executeFloaterSteps(handler.children)
}
```

### 全屏编辑

`ProgramMacroScreen` 已提供打开 `ProfessionalEditorScreen` 的入口（`fullscreenDialog: true`）。`FloaterEditorScreen` 缺少该入口，需在底部操作栏增加“全屏”按钮。

### 默认模板调整

当前模板主球 `singleClick(Launch_macro)`、副球无事件。需要：

- 主球单击切换副球可见性；
- 副球单击执行宏。

DSL 目前没有“切换显示”命令，需要新增 `toggle("name")` 步骤，否则模板会变得冗长（需要用变量记录状态并手写 if）。

### 卡片置顶

插件模型目前无置顶字段，需要在 `Plugin` 中新增 `pinned` 与 `pinnedAt`。设置页提供开关后，通过 `PluginProvider` 持久化，列表页按字段排序并变更颜色。

## 实现方案

### 1. 修复闪退（Android Kotlin）

文件：`android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt`

修改 `dispatchPluginBallEvent`：

```kotlin
private fun dispatchPluginBallEvent(name: String, event: String) {
    val handlers = pluginFloaterRegistry.get(event)
    if (handlers.isEmpty()) return
    for (handler in handlers) {
        mainHandler.post {
            executeFloaterSteps(handler.children)
        }
    }
}
```

### 2. 编程球编辑器全屏入口（Flutter）

文件：`lib/screens/floater_editor_screen.dart`

- 在底部校验/保存按钮旁增加“全屏”按钮；
- 点击后跳转 `ProfessionalEditorScreen`，返回结果后替换 `_codeController.text`；
- 参考 `ProgramMacroScreen._openProfessionalEditor()` 实现。

### 3. 新增 `toggle` DSL 命令并更新默认模板

#### 3.1 DSL 解析与序列化

文件：`lib/services/macro_program_parser.dart`

- `_normalizeStep` 中增加 `toggle` 分支；
- `_serializeStep` 中增加 `toggle` 序列化；
- 默认参数为球名。

#### 3.2 Kotlin 执行器

文件：`android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt`

在 `executeFloaterStep` 中增加：

```kotlin
"toggle" -> {
    val name = step["name"] as? String ?: return
    val ball = pluginBalls[name] ?: return
    setPluginBallVisible(name, !ball.visible)
}
```

#### 3.3 默认模板

文件：`lib/screens/floater_editor_screen.dart`

替换 `_template` 为：

```dsl
ball(main, "mainBall") {
    size(64)
    cornerRadius(16)
    image("main.png")
    location("mainBall", 100, 200)
    status(show, "mainBall")

    singleClick {
        toggle("helper")
    }

    doubleClick {
        launch("com.example.app", timeout=3000) {
        }
    }

    tripleClick(Turn_off_macros)

    longPress {
        print("长按主球")
    }
}

ball(deputy, "helper") {
    size(48)
    cornerRadius(24)
    image("helper.png")
    location("helper", 0, 0)
    status(hide, "helper")

    singleClick(Launch_macro)
}

// 副球显示在主球右侧
mainX = found("mainBall", x)
mainY = found("mainBall", y)
location("helper", mainX + 80, mainY)
```

### 4. 卡片置顶

#### 4.1 数据模型

文件：`lib/models/plugin.dart`

在 `Plugin` 中新增：

```dart
final bool pinned;
final DateTime? pinnedAt;
```

更新构造函数、`fromManifest`、`toJson`、`fromJson`，并增加 `copyWith`。

#### 4.2 持久化

文件：`lib/services/plugin_manager.dart`

新增：

```dart
Future<void> setPinned(String id, bool pinned) async {
    final plugin = _plugins.firstWhere((p) => p.id == id);
    plugin.pinned = pinned;
    plugin.pinnedAt = pinned ? DateTime.now() : null;
    await savePlugins();
}
```

> 由于 `Plugin` 字段目前多为 `final`，需要把 `pinned`/`pinnedAt` 设为非 final 或使用 copyWith。为减少改动，把这两个字段声明为 `bool pinned` 和 `DateTime? pinnedAt`（非 final）。

文件：`lib/providers/plugin_provider.dart`

新增包装方法：

```dart
Future<bool> updatePluginPin(String pluginId, bool pinned) async {
    await _manager.setPinned(pluginId, pinned);
    _plugins = List.from(_manager.plugins);
    notifyListeners();
    return true;
}
```

#### 4.3 设置页开关

文件：`lib/screens/macro_settings_screen.dart`、`lib/screens/floater_settings_screen.dart`

- 加载时读取 `plugin.pinned`；
- 增加“置顶卡片”开关卡片；
- 保存时调用 `provider.updatePluginPin(widget.pluginId, value)`。

#### 4.4 列表排序与颜色

文件：`lib/screens/home_screen.dart`、`lib/screens/manage_screen.dart`

排序逻辑：

```dart
List<Plugin> _sortedPlugins(List<Plugin> plugins) {
    final pinned = plugins.where((p) => p.pinned).toList()
      ..sort((a, b) => (b.pinnedAt ?? DateTime(0)).compareTo(a.pinnedAt ?? DateTime(0)));
    final unpinned = plugins.where((p) => !p.pinned).toList();
    return [...pinned, ...unpinned];
}
```

卡片颜色：置顶卡片使用 `Colors.black.withValues(alpha: 0.12)` 背景（比默认 `0.05` 深）。

## 文件改动清单

| 文件 | 改动 |
| --- | --- |
| `android/app/src/main/kotlin/com/example/isolation/FloatingBallService.kt` | 事件分发改为主线程；新增 `toggle` 步骤执行 |
| `lib/screens/floater_editor_screen.dart` | 增加全屏编辑按钮；更新默认 DSL 模板 |
| `lib/services/macro_program_parser.dart` | 解析与序列化 `toggle` 命令 |
| `lib/models/plugin.dart` | 新增 `pinned`、`pinnedAt` 字段 |
| `lib/services/plugin_manager.dart` | 新增 `setPinned` 方法 |
| `lib/providers/plugin_provider.dart` | 新增 `updatePluginPin` 方法；列表排序逻辑（或在 UI 层排序） |
| `lib/screens/macro_settings_screen.dart` | 增加置顶开关 |
| `lib/screens/floater_settings_screen.dart` | 增加置顶开关 |
| `lib/screens/home_screen.dart` | 按置顶状态/时间排序；置顶卡片颜色加深 |
| `lib/screens/manage_screen.dart` | 按置顶状态/时间排序；置顶卡片颜色加深 |

## 验证方式

1. 新建编程球并启用，点击主球应能正常切换副球显示/隐藏，不闪退。
2. 点击副球应能执行当前已启用的宏（无启用宏时提示“未启用宏”）。
3. 在编程球编辑器点击全屏按钮，能进入全屏编辑器并保存内容。
4. 在宏/编程球设置页打开“置顶卡片”，返回主页/管理区后该卡片排在最前且颜色变深。
5. 置顶多个卡片，后置顶的排在更前面。
