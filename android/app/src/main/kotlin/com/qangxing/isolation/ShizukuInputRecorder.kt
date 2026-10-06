package com.qangxing.isolation

import android.content.Context
import android.graphics.Point
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.SparseArray
import android.view.WindowManager
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Shizuku 高级录制：通过系统输入事件监听捕获真实触摸事件。
 *
 * 工作流程：
 * 1. 设备发现：用 Shizuku 执行 `getevent -il`，找到同时支持 ABS_MT_POSITION_X/Y 的触摸屏；
 * 2. 读取事件：用 Shizuku 执行 `getevent /dev/input/eventX`，逐行解析 Linux evdev 事件；
 * 3. 坐标映射：把触摸屏原始坐标按 maxX/maxY 映射到屏幕像素坐标；
 * 4. 手势识别：单指点击 / 长按 / 滑动；
 * 5. 步骤写入：识别完成后交给 [RecordingSession] 生成 DSL 步骤。
 *
 * 限制：读取 /dev/input/event* 在部分系统上需要 root 或特殊 SELinux 策略；
 * Shizuku 不自带 root，因此本模式在支持的环境中才能工作，否则会在日志中提示。
 */
object ShizukuInputRecorder {

    private const val TAG = "ShizukuInputRecorder"

    /** 判定为点击的最大位移（px） */
    private const val CLICK_SLOP_PX = 24
    /** 超过该时长且未移动 → 长按 */
    private const val LONG_PRESS_MS = 500L
    /** 最小滑动时长，避免把极短抖动识别为滑动 */
    private const val MIN_SWIPE_MS = 50L

    private val running = AtomicBoolean(false)
    private var workerThread: Thread? = null
    private var currentProcess: Process? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var contextRef: Context? = null

    /** 录制失败回调（如发现不到触摸设备、getevent 异常退出）。统一在主线程触发。 */
    fun interface OnErrorListener {
        fun onRecorderError(message: String)
    }

    @Volatile
    private var errorListener: OnErrorListener? = null

    /** 注册失败回调；传 null 清除。 */
    fun setOnErrorListener(listener: OnErrorListener?) {
        errorListener = listener
    }

    data class TouchDevice(
        val path: String,
        val name: String,
        val maxX: Int,
        val maxY: Int
    )

    private data class SlotState(
        val trackingId: Int,
        val downTime: Long,
        var downX: Int,
        var downY: Int,
        var x: Int,
        var y: Int,
        var gestureDispatched: Boolean = false
    )

    /** 是否正在通过 Shizuku 监听系统输入事件。 */
    fun isRunning(): Boolean = running.get()

    /**
     * 启动 Shizuku 高级录制。
     * 返回 true 表示开始尝试；实际能否读到事件取决于设备权限与 Shizuku 状态。
     */
    fun start(context: Context): Boolean {
        if (running.getAndSet(true)) return true
        if (!ShizukuHelper.toastIfNotReady(context)) {
            running.set(false)
            return false
        }
        contextRef = context.applicationContext
        workerThread = Thread({ recordLoop() }, "ShizukuInputRecorder").apply { start() }
        Log.d(TAG, "Shizuku 高级录制已启动")
        return true
    }

    /** 停止监听。 */
    fun stop() {
        if (!running.getAndSet(false)) return
        try {
            currentProcess?.destroy()
            currentProcess = null
        } catch (e: Exception) {
            Log.w(TAG, "停止 getevent 进程失败", e)
        }
        workerThread?.interrupt()
        workerThread = null
        contextRef = null
        Log.d(TAG, "Shizuku 高级录制已停止")
    }

    private fun recordLoop() {
        try {
            val device = discoverTouchDevice() ?: run {
                notifyError("未发现可读的触摸屏设备，getevent 可能无权限读取 /dev/input（请检查开发者选项中的权限监控相关设置）")
                return
            }
            Log.d(TAG, "使用触摸设备: ${device.path} (${device.name}), max=${device.maxX}x${device.maxY}")
            val stderr = readEvents(device)
            // readEvents 返回时 running 仍为 true，说明 getevent 进程非用户主动停止而退出
            if (running.get()) {
                val detail = stderr?.let { "：${it.trim()}" } ?: ""
                notifyError("getevent 进程意外退出，无法继续读取输入事件$detail")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Shizuku 录制循环异常", e)
            if (running.get()) {
                notifyError("Shizuku 录制异常：${e.message ?: e.javaClass.simpleName}")
            }
        } finally {
            running.set(false)
        }
    }

    /** 上报失败：打日志并在主线程回调（若已注册）。 */
    private fun notifyError(message: String) {
        Log.e(TAG, message)
        val listener = errorListener ?: return
        mainHandler.post { listener.onRecorderError(message) }
    }

    /** 运行 `getevent -il` 并解析出第一个支持多点触摸的输入设备。 */
    private fun discoverTouchDevice(): TouchDevice? {
        val proc = Shizuku.newProcess(arrayOf("/system/bin/getevent", "-il"), null, null)
        val reader = BufferedReader(InputStreamReader(proc.inputStream))
        val errReader = BufferedReader(InputStreamReader(proc.errorStream))
        var currentPath: String? = null
        var currentName: String? = null
        var maxX: Int? = null
        var maxY: Int? = null
        val addDeviceRegex = Regex("^add device \\d+: (/dev/input/event\\d+)$")
        val nameRegex = Regex("^  name:\\s+\"(.+)\"$")
        val absLineRegex = Regex("^\\s+ABS \\(0003\\):\\s+((?:[0-9a-fA-F]{4}\\s*)+)$")
        val absMaxRegex = Regex("^\\s+([0-9a-fA-F]{4})\\s+:\\s+value\\s+\\d+,\\s+min\\s+-?\\d+,\\s+max\\s+(\\d+),.*$")

        try {
            reader.useLines { lines ->
                for (line in lines) {
                    if (!running.get()) break
                    addDeviceRegex.matchEntire(line)?.let { m ->
                        // 发现新设备前，若上一个设备符合条件则直接返回
                        if (currentPath != null && maxX != null && maxY != null) {
                            return TouchDevice(currentPath!!, currentName ?: "", maxX!!, maxY!!)
                        }
                        currentPath = m.groupValues[1]
                        currentName = null
                        maxX = null
                        maxY = null
                        return@let
                    } ?: nameRegex.matchEntire(line)?.let {
                        currentName = it.groupValues[1]
                    } ?: absLineRegex.matchEntire(line)?.let {
                        // 仅用于确认当前段是 ABS，max 在下一行解析
                    } ?: absMaxRegex.matchEntire(line)?.let {
                        val code = it.groupValues[1].toInt(16)
                        val max = it.groupValues[2].toInt()
                        if (code == ABS_MT_POSITION_X) maxX = max
                        if (code == ABS_MT_POSITION_Y) maxY = max
                    }
                }
            }
            // 读完后再检查最后一个
            if (currentPath != null && maxX != null && maxY != null) {
                return TouchDevice(currentPath!!, currentName ?: "", maxX!!, maxY!!)
            }
            val err = errReader.readText().takeIf { it.isNotBlank() }
            if (err != null) Log.e(TAG, "getevent -il 错误: $err")
            return null
        } finally {
            try { proc.destroy() } catch (_: Exception) {}
        }
    }

    /** 读取指定设备的输入事件并识别手势。返回进程 stderr（无输出时为 null）。 */
    private fun readEvents(device: TouchDevice): String? {
        val proc = Shizuku.newProcess(arrayOf("/system/bin/getevent", device.path), null, null)
        currentProcess = proc
        val reader = BufferedReader(InputStreamReader(proc.inputStream))
        val errReader = BufferedReader(InputStreamReader(proc.errorStream))

        val slots = SparseArray<SlotState>()
        val pendingX = SparseArray<Int>()
        val pendingY = SparseArray<Int>()
        var currentSlot = 0
        var primarySlot: Int? = null

        reader.useLines { lines ->
            for (line in lines) {
                if (!running.get()) break
                val m = EVENT_LINE_REGEX.matchEntire(line) ?: continue
                val type = m.groupValues[1].toInt(16)
                val code = m.groupValues[2].toInt(16)
                val value = m.groupValues[3].toInt(16)

                when (type) {
                    EV_ABS -> when (code) {
                        ABS_MT_SLOT -> currentSlot = value
                        ABS_MT_POSITION_X -> pendingX.put(currentSlot, value)
                        ABS_MT_POSITION_Y -> pendingY.put(currentSlot, value)
                        ABS_MT_TRACKING_ID -> {
                            if (value == -1) {
                                if (currentSlot == primarySlot) {
                                    finalizeGesture(device, slots.get(currentSlot))
                                    primarySlot = null
                                }
                                slots.delete(currentSlot)
                                pendingX.delete(currentSlot)
                                pendingY.delete(currentSlot)
                            } else {
                                val now = SystemClock.elapsedRealtime()
                                val x = pendingX.get(currentSlot, 0)
                                val y = pendingY.get(currentSlot, 0)
                                val state = SlotState(
                                    trackingId = value,
                                    downTime = now,
                                    downX = x,
                                    downY = y,
                                    x = x,
                                    y = y
                                )
                                slots.put(currentSlot, state)
                                if (primarySlot == null) primarySlot = currentSlot
                            }
                        }
                    }
                    EV_KEY -> if (code == BTN_TOUCH && value == 0) {
                        // 所有手指抬起，结束主手指手势
                        primarySlot?.let {
                            finalizeGesture(device, slots.get(it))
                            slots.delete(it)
                            primarySlot = null
                        }
                        slots.clear()
                        pendingX.clear()
                        pendingY.clear()
                    }
                    EV_SYN -> if (code == SYN_REPORT) {
                        // 可在 SYN_REPORT 时更新连续坐标；当前方案抬手后统一识别手势
                    }
                }
            }
        }
        val err = errReader.readText().takeIf { it.isNotBlank() }
        if (err != null) Log.e(TAG, "getevent 错误: $err")
        return err
    }

    private fun finalizeGesture(device: TouchDevice, slot: SlotState?) {
        slot ?: return
        if (slot.gestureDispatched) return
        slot.gestureDispatched = true

        val ctx = contextRef ?: return
        val screen = screenSize(ctx)
        if (screen.x <= 0 || screen.y <= 0) return

        val startX = mapRawToScreen(slot.downX, device.maxX, screen.x)
        val startY = mapRawToScreen(slot.downY, device.maxY, screen.y)
        val endX = mapRawToScreen(slot.x, device.maxX, screen.x)
        val endY = mapRawToScreen(slot.y, device.maxY, screen.y)

        // 过滤录制悬浮球区域
        if (isInRecordingBallArea(endX, endY)) {
            Log.d(TAG, "忽略录制球区域触摸: ($endX, $endY)")
            return
        }

        val duration = (SystemClock.elapsedRealtime() - slot.downTime).coerceAtLeast(0L)
        val distance = hypot((endX - startX).toDouble(), (endY - startY).toDouble())

        Log.d(TAG, "识别手势 start=($startX,$startY) end=($endX,$endY) dist=$distance dur=$duration")

        mainHandler.post {
            if (!RecordingSession.isRecording()) return@post
            when {
                distance <= CLICK_SLOP_PX && duration < LONG_PRESS_MS -> {
                    RecordingSession.onTapCaptured(endX, endY)
                }
                distance <= CLICK_SLOP_PX && duration >= LONG_PRESS_MS -> {
                    RecordingSession.onLongPressCaptured(endX, endY, duration.coerceAtMost(800L))
                }
                duration >= MIN_SWIPE_MS -> {
                    RecordingSession.onSwipeCaptured(startX, startY, endX, endY, duration)
                }
                else -> {
                    // 极短抖动且位移小，降级为点击
                    RecordingSession.onTapCaptured(endX, endY)
                }
            }
        }
    }

    private fun mapRawToScreen(raw: Int, maxRaw: Int, screenPixels: Int): Int {
        if (maxRaw <= 0) return raw.coerceIn(0, screenPixels - 1)
        val v = (raw.toFloat() / maxRaw * screenPixels).roundToInt()
        return v.coerceIn(0, screenPixels - 1)
    }

    private fun screenSize(context: Context): Point {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            Point(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            Point().also { wm.defaultDisplay.getRealSize(it) }
        }
    }

    private fun isInRecordingBallArea(x: Int, y: Int): Boolean {
        return FloatingBallService.getRecordingBallExclusionRects().any { it.contains(x, y) }
    }

    // ── Linux evdev 常量 ──
    private const val EV_SYN = 0x0000
    private const val EV_KEY = 0x0001
    private const val EV_ABS = 0x0003

    private const val SYN_REPORT = 0x0000
    private const val BTN_TOUCH = 0x014a

    private const val ABS_MT_SLOT = 0x002f
    private const val ABS_MT_POSITION_X = 0x0035
    private const val ABS_MT_POSITION_Y = 0x0036
    private const val ABS_MT_TRACKING_ID = 0x0039

    /** getevent 单行正则：指定设备时无路径前缀，监控全部设备时带 `/dev/input/eventX: ` 前缀。 */
    private val EVENT_LINE_REGEX = Regex("^(?:/dev/input/event\\d+:\\s+)?([0-9a-fA-F]{4})\\s+([0-9a-fA-F]{4})\\s+([0-9a-fA-F]{8})$")
}
