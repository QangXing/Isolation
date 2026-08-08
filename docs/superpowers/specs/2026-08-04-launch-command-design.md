# 新增 launch 应用启动指令设计

## 背景
Isolation 宏脚本需要能够主动打开其他应用，并在目标应用出现后继续执行后续步骤。

## 目标
新增 `launch(packageName, timeout?)` 指令，支持：
- 通过包名启动任意已安装应用
- 可选阻塞等待目标应用窗口出现
- 返回布尔结果，可用于变量赋值或条件判断

## DSL 语法

```dsl
launch("com.example.app")                 // 启动，不等待
launch("com.example.app", timeout=3000)   // 启动并等待 3 秒
let ok = launch("com.example.app", timeout=3000)
if (launch("com.example.app", timeout=3000)) {
    click(500, 800)
}
```

参数说明：
- `packageName`（位置参数，必填）：目标应用包名，字符串
- `timeout`（命名参数，可选）：最长等待毫秒数，默认 `0`（不等待）

## 执行语义

1. 构造 `Intent(Intent.ACTION_MAIN)` 并设置 `CATEGORY_LAUNCHER` 与目标包名
2. 调用 `service.startActivity(intent)` 启动应用
3. 若 `timeout > 0`：
   - 每 200ms 检查一次当前 Accessibility 根节点包名
   - 若包名匹配则立即返回 `1`
   - 超时时返回 `0`
4. 若 `timeout == 0`：直接返回 `1`

## 返回值

- 命中/启动成功：`1`
- 超时/未出现：`0`

返回值可用于：
- `let ok = launch(...)`
- `if (launch(...)) { ... }`
- `ifText` / `ifColor` 等条件中暂不使用

## 影响文件

- `lib/services/macro_program_parser.dart`：解析 `launch` 的位置参数与 `timeout`
- `lib/services/macro_syntax_highlighter.dart`：添加 `launch` 关键字高亮
- `android/app/src/main/kotlin/com/example/isolation/MacroExecutor.kt`：新增 `executeLaunchStep`
- `lib/screens/program_macro_screen.dart`：编辑器快捷插入 chips 增加 `launch`
- `docs/DSL_SPEC.md`：新增 `launch` 指令说明
- `test/services/macro_program_parser_test.dart`：新增 round-trip 测试

## 权限

无需额外权限。`startActivity` 启动其他应用使用 Android 标准 Intent。
