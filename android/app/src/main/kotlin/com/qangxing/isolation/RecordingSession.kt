package com.qangxing.isolation

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 录制会话协调器：持有录制状态机（IDLE/RECORDING/PAUSED/FINISHED）、
 * 录制参数与原始步骤，并负责结束录制后的指令后处理与结果持久化。
 *
 * 协作关系：
 * - [RecordingCaptureOverlay]：全屏手势捕获层，判定手势后调用 onTapCaptured / onLongPressCaptured / onSwipeCaptured；
 * - [InputAccessibilityService]：回放点击后回调 enrichLastClick 用真实节点补全 click 步骤（复杂模式升级为 clickNode）；
 * - [FloatingBallService]：录制悬浮球（主球 + 开始/暂停 + 结束副球），状态变化时同步图标。
 */
object RecordingSession {

    enum class State { IDLE, RECORDING, PAUSED, FINISHED }

    enum class Mode { SIMPLE, COMPLEX }

    private const val TAG = "RecordingSession"
    private const val RESULT_FILE = "pending_record_result.json"
    private const val RESULT_VERSION = 1

    @Volatile
    var state: State = State.IDLE
        private set

    var mode: Mode = Mode.SIMPLE
        private set
    var captureColors: Boolean = false
        private set
    var recordSystemKeys: Boolean = true
        private set
    var minClickIntervalMs: Long = 100L
        private set
    var replayGestures: Boolean = true
        private set

    /** 是否使用全屏手势捕获层。true 时背景不可直接点击，但能录滑动/拖拽等原始手势。 */
    var gestureMode: Boolean = false
        private set

    /** 是否使用 Shizuku 高级录制（读取系统输入事件）。与手势捕获层互斥。 */
    var shizukuMode: Boolean = false
        private set

    /** 录制的原始步骤（含时间戳，供 [RecordingPostProcessor] 按模式产出 DSL 指令） */
    data class RawStep(
        val timestamp: Long,
        val step: MutableMap<String, Any?>
    )

    private val rawSteps = mutableListOf<RawStep>()
    private var lastClickStep: RawStep? = null
    private var lastRawTimestamp = 0L
    private var pauseStartedAt = 0L
    private var defaultBallVisibleBefore = false

    private var contextRef: Context? = null

    val stepCount: Int get() = rawSteps.size

    // ── 状态机 ──

    /**
     * 开始录制：挂载捕获层（保证层级低于录制球）→ 展示录制悬浮球。
     * 录制参数页点"开始录制"后由 MainActivity 通道调用。
     */
    fun start(
        ctx: Context,
        modeName: String,
        captureColors: Boolean,
        recordSystemKeys: Boolean,
        minClickIntervalMs: Long,
        replayGestures: Boolean,
        gestureMode: Boolean = false,
        shizukuMode: Boolean = false
    ): Boolean {
        if (state == State.RECORDING || state == State.PAUSED) return false
        contextRef = ctx.applicationContext
        this.mode = if (modeName == "complex") Mode.COMPLEX else Mode.SIMPLE
        // 颜色捕获仅复杂模式可用
        this.captureColors = captureColors && this.mode == Mode.COMPLEX
        this.recordSystemKeys = recordSystemKeys
        this.minClickIntervalMs = minClickIntervalMs.coerceAtLeast(0L)
        this.replayGestures = replayGestures
        // Shizuku 模式与手势捕获层互斥：优先使用 Shizuku 系统输入事件
        this.shizukuMode = shizukuMode
        this.gestureMode = gestureMode && !shizukuMode
        rawSteps.clear()
        lastClickStep = null
        lastRawTimestamp = 0L
        pauseStartedAt = 0L

        // 确保悬浮球服务在运行（录制参数页发起时服务可能尚未启动），用于承载录制球
        FloatingBallService.ensureServiceRunning(ctx)
        // 先收起可能存在的默认悬浮球，避免与录制球重叠，结束后再恢复
        defaultBallVisibleBefore = FloatingBallService.hideDefaultBallForRecording()
        // 手势模式下挂载全屏捕获层；Shizuku 模式下直接读取系统输入事件，不需要覆盖层
        if (shizukuMode) {
            // 注册失败回调：getevent 读不到输入事件时提示用户并降级为手势捕获层
            ShizukuInputRecorder.setOnErrorListener { message -> onShizukuRecorderError(message) }
            if (!ShizukuInputRecorder.start(ctx)) {
                // Shizuku 未就绪（未安装/未运行/未授权），toastIfNotReady 已提示原因，
                // 此处不再整体放弃录制，而是降级为手势捕获层保证本次录制可用
                ShizukuInputRecorder.setOnErrorListener(null)
                this.shizukuMode = false
                this.gestureMode = true
                RecordingCaptureOverlay.show(ctx)
            }
        } else if (gestureMode) {
            RecordingCaptureOverlay.show(ctx)
        }
        FloatingBallService.ensureRecordingBalls(ctx)

        state = State.RECORDING
        Log.d(TAG, "录制开始 mode=$mode captureColors=$captureColors gestureMode=$gestureMode shizukuMode=$shizukuMode")
        return true
    }

    fun pause() {
        if (state != State.RECORDING) return
        state = State.PAUSED
        pauseStartedAt = SystemClock.elapsedRealtime()
        // 手势模式暂停时移除捕获层；Shizuku 模式暂停时停止输入事件监听
        when {
            shizukuMode -> ShizukuInputRecorder.stop()
            gestureMode -> RecordingCaptureOverlay.hide()
        }
        FloatingBallService.updateRecordingBallState()
        Log.d(TAG, "录制暂停")
    }

    fun resume() {
        if (state != State.PAUSED) return
        val ctx = contextRef ?: return
        state = State.RECORDING
        // 暂停时长不计入步骤间隔：把计时基准整体后移
        if (pauseStartedAt > 0L) {
            lastRawTimestamp += SystemClock.elapsedRealtime() - pauseStartedAt
            pauseStartedAt = 0L
        }
        when {
            shizukuMode -> {
                // 恢复时 Shizuku 可能已不可用（如服务被杀），启动失败则降级为手势捕获层
                ShizukuInputRecorder.setOnErrorListener { message -> onShizukuRecorderError(message) }
                if (!ShizukuInputRecorder.start(ctx)) {
                    ShizukuInputRecorder.setOnErrorListener(null)
                    shizukuMode = false
                    gestureMode = true
                    RecordingCaptureOverlay.show(ctx)
                }
            }
            gestureMode -> RecordingCaptureOverlay.show(ctx)
        }
        FloatingBallService.updateRecordingBallState()
        Log.d(TAG, "录制继续")
    }

    fun isRecording(): Boolean = state == State.RECORDING

    /**
     * Shizuku 输入监听失败（在主线程回调）：Toast 告知原因，并把本次录制降级为
     * 手势捕获层模式继续，避免录制球显示中但触摸完全无记录的"假死"状态。
     */
    private fun onShizukuRecorderError(message: String) {
        if (!isRecording() || !shizukuMode) return
        val ctx = contextRef ?: return
        Log.w(TAG, "Shizuku 录制失败，降级为手势捕获模式: $message")
        ShizukuInputRecorder.stop()
        ShizukuInputRecorder.setOnErrorListener(null)
        shizukuMode = false
        gestureMode = true
        RecordingCaptureOverlay.show(ctx)
        Toast.makeText(ctx, "Shizuku 录制不可用，已降级为手势捕获模式\n$message", Toast.LENGTH_LONG).show()
    }

    // ── 步骤收集 ──

    /** 捕获层判定为点击 */
    fun onTapCaptured(x: Int, y: Int) {
        if (!isRecording()) return
        val now = SystemClock.elapsedRealtime()
        // 最小点击间隔：过滤过密的连点
        val last = lastClickStep
        if (last != null && now - last.timestamp < minClickIntervalMs) return
        val step = newStep(now)
        step["type"] = "click"
        step["x"] = x
        step["y"] = y
        lastClickStep = addStep(step, now)
    }

    /** 捕获层判定为长按 */
    fun onLongPressCaptured(x: Int, y: Int, duration: Long) {
        if (!isRecording()) return
        val now = SystemClock.elapsedRealtime()
        val step = newStep(now)
        step["type"] = "longPressAt"
        step["x"] = x
        step["y"] = y
        step["duration"] = duration.coerceAtLeast(300L)
        addStep(step, now)
    }

    /** 捕获层判定为滑动 */
    fun onSwipeCaptured(startX: Int, startY: Int, endX: Int, endY: Int, duration: Long) {
        if (!isRecording()) return
        val now = SystemClock.elapsedRealtime()
        val step = newStep(now)
        step["type"] = "swipe"
        step["start"] = mapOf("x" to startX, "y" to startY)
        step["end"] = mapOf("x" to endX, "y" to endY)
        step["duration"] = duration.coerceAtLeast(50L)
        addStep(step, now)
    }

    /**
     * 辅助服务捕获到节点点击事件（非手势模式时使用）。
     * 复杂模式下直接升级为 clickNode；简单模式退化为坐标 click。
     */
    fun onAccessibilityClickCaptured(
        centerX: Int,
        centerY: Int,
        target: Map<String, Any?>,
        sourcePackage: String
    ) {
        if (!isRecording()) return
        // 避免录到自己 App 的界面
        val ctx = contextRef ?: return
        if (sourcePackage == ctx.packageName) return
        val now = SystemClock.elapsedRealtime()
        val last = lastClickStep
        if (last != null && now - last.timestamp < minClickIntervalMs) return
        val step = newStep(now)
        if (mode == Mode.COMPLEX) {
            step["type"] = "clickNode"
            step["target"] = target.filterValues { it != null }
            if (captureColors) {
                val color = ScreenCaptureHelper.captureColor(ctx, centerX, centerY)
                if (color != null) {
                    step["color"] = mapOf("x" to centerX, "y" to centerY, "color" to color)
                }
            }
        } else {
            step["type"] = "click"
            step["x"] = centerX
            step["y"] = centerY
        }
        lastClickStep = addStep(step, now)
    }

    /** 辅助服务捕获到滚动事件，记录为 scroll 步骤。 */
    fun onScrollCaptured(
        centerX: Int,
        centerY: Int,
        deltaX: Int,
        deltaY: Int,
        sourcePackage: String
    ) {
        if (!isRecording()) return
        val ctx = contextRef ?: return
        if (sourcePackage == ctx.packageName) return
        val now = SystemClock.elapsedRealtime()
        val step = newStep(now)
        step["type"] = "scroll"
        step["x"] = centerX
        step["y"] = centerY
        step["deltaX"] = deltaX
        step["deltaY"] = deltaY
        addStep(step, now)
    }

    /** 录制悬浮球"标记"按钮：在脚本中插入一个 print 标记步骤，便于后期在编辑页定位关键节点。 */
    fun addMark() {
        if (!isRecording()) return
        val now = SystemClock.elapsedRealtime()
        val step = newStep(now)
        step["type"] = "mark"
        step["name"] = "标记 ${rawSteps.count { it.step["type"] == "mark" } + 1}"
        addStep(step, now)
    }

    /** 系统键（back/home）：由辅助服务检测到返回键 / Home 键按下时调用 */
    fun onSystemKey(type: String) {
        if (!isRecording()) return
        if (!recordSystemKeys) return
        val now = SystemClock.elapsedRealtime()
        val step = newStep(now)
        step["type"] = type
        addStep(step, now)
    }

    /**
     * 辅助服务在捕获层点击回放后，用真实节点信息补全最近一次点击步骤：
     * - 复杂模式：升级为 clickNode（Flutter 侧 convertLegacySteps 会转换为 findText / ifColorAt 增强指令）；
     * - 简单模式：保留坐标 click。
     * 坐标容差用于避免匹配到相邻的旧点击。
     */
    fun enrichLastClick(target: Map<String, Any?>, centerX: Int, centerY: Int) {
        val step = lastClickStep ?: return
        if (step.step["type"] != "click") return
        val sx = (step.step["x"] as? Number)?.toInt() ?: return
        val sy = (step.step["y"] as? Number)?.toInt() ?: return
        if (kotlin.math.abs(sx - centerX) > 80 || kotlin.math.abs(sy - centerY) > 80) return
        if (mode != Mode.COMPLEX) return
        val ctx = contextRef ?: return
        step.step["type"] = "clickNode"
        step.step["target"] = target
        if (captureColors) {
            val color = ScreenCaptureHelper.captureColor(ctx, centerX, centerY)
            if (color != null) {
                step.step["color"] = mapOf("x" to centerX, "y" to centerY, "color" to color)
            }
        }
        lastClickStep = null
    }

    // ── 结束 / 取消 ──

    /** 结束录制：指令后处理 → 补齐收尾 wait → 持久化待处理结果 → 收起悬浮球 → 打开主界面跳转结果编辑页 */
    fun finish() {
        if (state == State.IDLE) return
        val ctx = contextRef ?: return
        val wasPaused = state == State.PAUSED
        state = State.FINISHED
        // 统一清理：Shizuku 输入监听 / 全屏手势捕获层
        ShizukuInputRecorder.setOnErrorListener(null)
        ShizukuInputRecorder.stop()
        RecordingCaptureOverlay.hide()
        val steps = RecordingPostProcessor.process(rawSteps, mode, captureColors).toMutableList()
        // 收尾等待：最后一步到点"结束"的间隔没有任何步骤承载，补为 wait，
        // 否则宏循环播放时最后一轮到第一轮之间的节拍会丢失
        if (rawSteps.isNotEmpty() && lastRawTimestamp > 0L) {
            val now = SystemClock.elapsedRealtime()
            // 从暂停状态直接结束时，暂停时长不计入收尾等待
            val reference = if (wasPaused && pauseStartedAt > 0L) pauseStartedAt else now
            val trailing = (reference - lastRawTimestamp).coerceIn(0L, 600_000L)
            // 过短的收尾间隔视为"录完即停"，不生成 wait 噪音
            if (trailing >= 500L) {
                steps.add(mapOf("type" to "wait", "duration" to trailing))
            }
        }
        persistResult(ctx, steps)
        FloatingBallService.endRecordingMode(restoreDefaultBall = defaultBallVisibleBefore)
        Log.d(TAG, "录制结束，共 ${steps.size} 步")
        openMainActivity(ctx)
    }

    /** 取消录制：丢弃结果，清理捕获层与录制球 */
    fun cancel() {
        if (state == State.IDLE && rawSteps.isEmpty()) return
        state = State.IDLE
        ShizukuInputRecorder.setOnErrorListener(null)
        ShizukuInputRecorder.stop()
        RecordingCaptureOverlay.hide()
        FloatingBallService.endRecordingMode(restoreDefaultBall = defaultBallVisibleBefore)
        rawSteps.clear()
        lastClickStep = null
        contextRef = null
        Log.d(TAG, "录制取消")
    }

    fun stateMap(): Map<String, Any?> {
        return mapOf(
            "state" to state.name.lowercase(),
            "stepCount" to rawSteps.size,
            "mode" to mode.name.lowercase(),
            "shizukuMode" to shizukuMode,
            "gestureMode" to gestureMode
        )
    }

    // ── 结果持久化（供 Flutter 拉取） ──

    private fun persistResult(ctx: Context, steps: List<Map<String, Any>>) {
        try {
            val arr = JSONArray()
            for (s in steps) arr.put(JSONObject(s))
            val obj = JSONObject().apply {
                put("version", RESULT_VERSION)
                put("mode", mode.name.lowercase())
                put("steps", arr)
            }
            File(ctx.filesDir, RESULT_FILE).writeText(obj.toString())
        } catch (e: Exception) {
            Log.e(TAG, "持久化录制结果失败", e)
        }
    }

    /** 读取并消费待处理录制结果（Flutter 拉取后文件即被清除） */
    fun consumePendingResult(ctx: Context): JSONObject? {
        val file = File(ctx.filesDir, RESULT_FILE)
        if (!file.exists()) return null
        return try {
            val obj = JSONObject(file.readText())
            file.delete()
            obj
        } catch (e: Exception) {
            file.delete()
            null
        }
    }

    // ── 内部 ──

    /** 生成步骤并计算与上一步的间隔（delay，即回放时等待的毫秒数）。上限放宽到 10 分钟，确保长等待被精确记录。 */
    private fun newStep(now: Long): MutableMap<String, Any?> {
        val delay = if (lastRawTimestamp == 0L) 0L else (now - lastRawTimestamp).coerceIn(0L, 600_000L)
        lastRawTimestamp = now
        return mutableMapOf("type" to "", "delay" to delay)
    }

    private fun addStep(step: MutableMap<String, Any?>, now: Long): RawStep {
        val rs = RawStep(now, step)
        rawSteps.add(rs)
        return rs
    }

    private fun openMainActivity(ctx: Context) {
        try {
            val intent = Intent(ctx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            ctx.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "打开主界面失败", e)
        }
    }
}
