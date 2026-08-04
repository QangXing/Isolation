# Isolation 宏 DSL 语法规范（v2 提案）

> 本文档用于统一、清晰地说明 Isolation 宏脚本支持的全部语法。当前版本是对原有 `find(...)` 过载用法的梳理与优化，让“查找、等待、判断、取值”各司其职，脚本更易读、易维护。
>
> 旧 `find(...)` 过载语法不再兼容，新脚本请按本文档书写。

---

## 1. 设计原则

1. **一个命令只做一件事**：查询、等待、判断、点击不再混在同一个 `find(...)` 里。
2. **语义直观**：看到命令名就能知道它返回坐标、颜色、布尔值，还是直接执行动作。
3. **参数统一**：所有查找类命令都支持 `region`、`tolerance`、`step`、`timeout` 等通用参数。
4. **不保留旧兼容**：旧写法（如 `find(text="...")`、`find(loop)`）不再支持，请直接使用新命令。

---

## 2. 基础动作指令

| 语法 | 说明 | 示例 |
|---|---|---|
| `click(x, y)` | 点击指定坐标 | `click(500, 800)` |
| `click()` | 点击最近一次查询/查找得到的坐标，只能出现在查找块内 | `findText("签到") { click() }` |
| `swipe(dx, dy, duration)` | 从屏幕中心按相对偏移滑动 | `swipe(0, 300, 400)` |
| `swipe(fromX, fromY, dx, dy, duration)` | 从指定起点按相对偏移滑动 | `swipe(500, 800, 0, -300, 400)` |
| `swipe(x1, y1, x2, y2, duration)` | 从起点滑动到终点 | `swipe(500, 180, 100, 180, 300)` |
| `input("文字")` | 在已聚焦输入框输入文字 | `input("Hello")` |
| `wait(ms)` | 暂停指定毫秒 | `wait(1000)` |
| `print("文字")` | 输出调试日志 | `print("开始任务")` |
| `back()` / `home()` / `recents()` | 系统按键 | `back()` |

> 坐标、颜色、时间等数值都支持纯数字、变量或表达式，例如 `click(x + 10, y - 20)`。

---

## 3. 查找与等待指令

查找类命令用于在屏幕上定位目标，返回坐标；命令块内的 `click()` 会自动使用这个坐标。

### 3.1 按文字查找

```dsl
findText("签到") {
  click()
  wait(500)
}
```

通用参数：
- `region=[x1, y1, x2, y2]`：限定查找区域。

```dsl
findText("确定", region=[100, 500, 900, 1100]) { click() }
```

### 3.2 按颜色查找

```dsl
findColor(0xFF5000, tolerance=20) { click() }
```

参数：
- `tolerance`：每个通道允许的色差，默认 20。
- `step`：扫描步长，默认 2；值越小越精确但越慢。
- `region=[x1, y1, x2, y2]`：限定区域，可显著加速。

```dsl
findColor(0xFFFA40, tolerance=30, step=1, region=[100, 1000, 1000, 1800]) { click() }
```

### 3.3 按图片查找

```dsl
findImage("btn.png") { click() }
```

参数：
- `featureCount`：特征点采样数目，默认 8。
- `featurePointThreshold`：特征点匹配比例阈值，默认 0.8（80%）。
- `colorTolerance`：颜色容差，默认 20。
- `region=[x1, y1, x2, y2]`：限定查找区域。

```dsl
findImage("icon.png", featureCount=12, featurePointThreshold=0.9, colorTolerance=25) { click() }
```

图片匹配原理：
- 以参考图中心为原点，自动选取颜色最稀有、位于色块分界线的点作为特征点。
- 距离原点最远的特征点作为主参考点，导入后缓存特征数据。
- 搜索时先找主参考点，再沿原点方向匹配原点颜色以自动计算缩放比例，最后校验副参考点。

### 3.4 等待目标出现（执行一次）

```dsl
waitForText("加载完成") { click() }
waitForColor(0xFFFA40, step=1) { click() }
waitForImage("ok.png") { click() }
```

- 循环查找，直到命中后执行一次块内指令。
- 比旧写法 `find(text="...", loop)` 更直观。

### 3.5 无限循环

```dsl
loop {
  findText("签到") {
    click()
    wait(1000)
  }
}
```

- 无限循环执行块内指令，直到手动停止。

---

## 4. 颜色取值与判断

### 4.1 读取指定坐标颜色

```dsl
c = colorAt(500, 800)
print(c)
```

- 返回坐标点的颜色值（ARGB 整数）。
- 坐标支持变量或表达式：`colorAt(x, y)`。

### 4.2 判断坐标颜色

```dsl
ifColorAt(500, 800, 0xFF5000, tolerance=20) {
  click()
}
```

- 若指定坐标颜色匹配，则执行 then 块。
- 也支持 `else`。

```dsl
ifColorAt(500, 800, 0xFF5000, tolerance=20) {
  click()
} else {
  print("颜色不匹配")
}
```

---

## 5. 条件判断

条件指令直接表达“如果屏幕上有/没有某目标”。

```dsl
ifText("同意") { click() } else { print("未找到") }
ifColor(0xFF5000, tolerance=20) { click() }
ifImage("popup.png") { click() }
```

也支持通用 `if` 表达式：

```dsl
if (findText("同意")) { click() }
if (findColor(0xFF5000)) { click() }
if (findImage("popup.png")) { click() }
```

---

## 6. 变量与赋值

使用 `let` 声明变量，类型由右侧表达式自动决定。

```dsl
let p = findImage("btn.png")      // point
let c = colorAt(100, 200)         // int 颜色
let ok = findText("原神")          // bool（命中为 1，未命中为 0）

click(p.x, p.y)
print(c)
if (ok) { click() }
```

### 支持的变量类型

- `point`：坐标，可通过 `.x`、`.y` 访问。
- `int` / `double`：数值。
- `bool`：由条件或查找结果转换得到。

---

## 7. 循环

### 7.1 固定次数循环

```dsl
for (3) {
  swipe(0, 300, 400)
  wait(500)
}
```

### 7.2 C 风格循环

```dsl
for (int i = 0; i < 10; i = i + 1) {
  click(500 + i * 10, 800)
}
```

---

## 8. 完整示例

```dsl
// 等待“加载完成”出现后点击
waitForText("加载完成") {
  click()
}

// 读取某个点的颜色，判断后再点击
let c = colorAt(500, 800)
print(c)
ifColorAt(500, 800, 0xFFFA40, tolerance=30) {
  click(971, 1281)
}

// 按图片查找并点击
let p = findImage("start.png", featureCount=12)
click(p.x, p.y)

// 无限轮询签到
loop {
  waitForText("签到") { click() }
  wait(2000)
}
```

---

## 9. 参数速查表

| 参数 | 适用命令 | 默认值 | 说明 |
|---|---|---|---|
| `tolerance` | `findColor`、`ifColorAt` | 20 | 颜色通道容差 |
| `step` | `findColor`、`ifColorAt` | 2 | 扫描步长 |
| `region=[x1,y1,x2,y2]` | 所有查找/判断命令 | 全屏 | 限定查找区域 |
| `featureCount` | `findImage`、`waitForImage` | 8 | 特征点数量 |
| `featurePointThreshold` | `findImage`、`waitForImage` | 0.8 | 特征点匹配比例 |
| `colorTolerance` | `findImage`、`waitForImage` | 20 | 特征点颜色容差 |
| `timeout` | `waitForText` 等 | 无 | 最长等待时间（毫秒） |
