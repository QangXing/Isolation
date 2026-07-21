# 编程宏 `find(image=...)` 图片查找指令设计草案

> 状态：已实现  
> 日期：2026-07-21

---

## 一、目标

在现有 `find(color=...)` 与 `find(text="...")` 的基础上，新增图片匹配能力：

```dsl
find(image="button_login.jpg") {
    click()
}
```

宏执行时，在屏幕上寻找与导入图片相似的目标，命中后把目标中心坐标压入坐标栈，子块可像现有 `find` 一样使用 `click()` 点击中心。

---

## 二、使用场景

- 目标没有稳定文字或颜色，但有固定图标/按钮样式。
- 颜色识别受主题/动态背景干扰，想用整张局部截图提高命中率。
- 需要等待某个界面/弹窗出现后再操作。

---

## 三、语法设计

### 3.1 基本用法

```dsl
find(image="icon_coin.jpg") {
    click()
}
```

### 3.2 带阈值与搜索区域（可选）

```dsl
find(
    image="icon_coin.jpg",
    threshold=0.85,
    region=[100, 200, 900, 1200]
) {
    click()
}
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `image` | string | 是 | 导入图片文件名（存在插件目录内） |
| `threshold` | float | 否 | 相似度阈值，0.0 ~ 1.0，默认 0.80 |
| `region` | list[int] | 否 | 搜索区域 `[left, top, right, bottom]`，未指定则全屏 |

### 3.3 与现有 `find` 的关系

`find` 块内同时只能有一种匹配方式：

- `find(color=...)`：按颜色查找。
- `find(target=...)`：按 Accessibility 节点查找。
- `find(image=...)`：按图片模板查找（新增）。

执行引擎按参数优先级判定：

1. 若存在 `image`，走图片匹配。
2. 否则若存在 `color`，走颜色匹配。
3. 否则若存在 `target`，走节点匹配。

---

## 四、编程宏中的图片导入

### 4.1 导入入口

在 `ProgramMacroScreen` 编辑器中增加“导入图片”按钮，允许从相册选择一张图片作为模板。

### 4.2 存储方式

- 图片随宏插件一起保存到插件目录，例如：
  ```
  plugins/<plugin_id>/assets/icon_coin.jpg
  ```
- `find(image=...)` 中的文件名为相对路径，执行时从插件目录解析。
- 导出 `.isoplugin` 时图片作为资源打包。

### 4.3 尺寸限制与裁剪

为避免导入图片过大导致匹配过慢、内存占用高，采用**方案 C：用户手动裁剪 + 输出尺寸上限**。

- 导入图片后进入裁剪页，用户可以拖动和缩放矩形裁剪框，框选目标区域。
- 裁剪完成后，输出图片最长边不超过 320px，等比缩放（默认 `maxOutputSize = 320`）。
- 该上限既保证模板足够清晰，又避免 `matchTemplate` 在全屏大图上耗时过长。

---

## 五、匹配算法

### 5.1 基础流程

1. 通过 `MediaProjection` 获取当前屏幕帧（复用 `ScreenCaptureHelper` 的缓存）。
2. 将屏幕帧与模板图片都转为灰度或保持 RGB。
3. 在指定 `region` 或全屏范围内进行模板匹配。
4. 找到最佳匹配位置，计算中心坐标。
5. 若最大相似度 >= `threshold`，压栈并执行子块；否则提示未命中。

### 5.2 候选算法

| 算法 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| 模板匹配（TM_CCOEFF_NORMED） | 实现简单、OpenCV 直接支持 | 对缩放/旋转敏感 | 固定大小图标 |
| 特征点匹配（ORB/SIFT） | 抗缩放、旋转、轻微遮挡 | 计算量大、需要额外库 | 复杂 UI 元素 |
| 感知哈希（pHash/aHash） | 快、抗轻微压缩 | 只能判断相似，不能定位 | 全屏截图比对 |

**当前倾向**：先用 OpenCV 的 `TM_CCOEFF_NORMED` 模板匹配；若后续对缩放/旋转有需求，再引入 ORB 或允许用户指定缩放比例。

### 5.3 性能优化：避免全屏逐像素比较

用户提到“不需要把全屏全部内容都比较”。可考虑以下优化：

1. **指定搜索区域 `region`**：用户手动限定大概范围，大幅减少搜索面积。
2. **金字塔分层搜索**：先对缩略图快速定位候选区域，再在原分辨率精细匹配。
3. **步长采样**：模板匹配时以 2px 或 4px 为步长扫描，牺牲少量精度换取速度。
4. **仅匹配灰度**：减少通道数，降低计算量。
5. **单次匹配上限**：例如最多搜索 3 秒未命中即放弃，避免长时间阻塞。

**实现建议**：
- 第一阶段先支持 `region` + 灰度 + 步长 2 的模板匹配。
- 金字塔优化作为第二阶段迭代。

---

## 六、实现文件

| 文件 | 说明 |
|------|------|
| [android/app/build.gradle.kts](file:///workspace/Isolation/android/app/build.gradle.kts) | 添加 OpenCV 依赖 `org.opencv:opencv:4.12.0` |
| [android/app/src/main/kotlin/com/example/isolation/MainActivity.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MainActivity.kt) | 静态初始化 OpenCV |
| [android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ImageFinder.kt) | OpenCV 模板匹配实现 |
| [android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt) | `executeFindStep` 新增 `image` 分支 |
| [android/app/src/main/kotlin/com/example/isolation/ScreenCaptureHelper.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/ScreenCaptureHelper.kt) | 提供 `getLatestFrame()` 给 `ImageFinder` |
| [android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt](file:///workspace/Isolation/android/app/src/main/kotlin/com/example/isolation/InputAccessibilityService.kt) | 透传 `assetsDir` 给 `MacroExecutor` |
| [lib/services/native_channel.dart](file:///workspace/Isolation/lib/services/native_channel.dart) | `executeMacro` 增加 `assetsDir` 参数 |
| [lib/providers/plugin_provider.dart](file:///workspace/Isolation/lib/providers/plugin_provider.dart) | 插件资源目录管理、保存时保留 assets |
| [lib/screens/program_macro_screen.dart](file:///workspace/Isolation/lib/screens/program_macro_screen.dart) | 图片导入按钮、资源列表、点击插入代码 |
| [lib/screens/image_crop_screen.dart](file:///workspace/Isolation/lib/screens/image_crop_screen.dart) | 手动裁剪页，输出最长边不超过 320px |
| [lib/services/macro_program_parser.dart](file:///workspace/Isolation/lib/services/macro_program_parser.dart) | 支持 `image` / `threshold` / `region` 参数序列化与列表字面量解析 |

---

## 七、待决策事项（已实现后仍可能迭代）

1. **默认相似度阈值**：0.80 是否足够宽松/严格？
2. **是否支持多模板**：例如 `find(image=["a.jpg", "b.jpg"])` 命中任一即可？
3. **是否支持点击偏移**：例如 `click(offsetX=10, offsetY=-5)`？
4. **性能优化**：是否需要加入金字塔分层或步长采样进一步提升速度？
