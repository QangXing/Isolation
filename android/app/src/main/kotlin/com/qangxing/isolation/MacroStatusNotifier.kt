package com.qangxing.isolation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject

/**
 * 通知栏状态通知：展示 Isolation 运行状态，并实时展示宏执行中的 `print` 输出。
 *
 * - 开关由 Flutter 设置页控制（[configure]），并持久化到原生 SharedPreferences，
 *   使后台（定时触发 / 进程重建 / 开机自启）场景下也能按开关生效。
 * - 通过 [MacroExecutorListener] 订阅宏生命周期与 print 输出；
 *   悬浮球 / 辅助服务生命周期变化时调用 [refreshState] 刷新状态行。
 */
object MacroStatusNotifier : MacroExecutorListener {

    private const val TAG = "MacroStatusNotifier"
    private const val CHANNEL_ID = "isolation_status"
    private const val NOTIFICATION_ID = 3
    private const val PREF_NAME = "isolation_ui_prefs"
    private const val KEY_ENABLED = "status_notification_enabled"
    private const val MAX_PRINT_LINES = 5

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var enabled = false

    @Volatile
    private var runningPluginId: String? = null

    @Volatile
    private var runningPluginName: String? = null

    private val printLines = mutableListOf<String>()
    private var registered = false

    // ==== 开关 ====

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    /** 读取开关状态（供后台场景自行判断，不依赖 Flutter 侧调用）。 */
    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, false)

    /** 由 Flutter 设置页调用：开启 / 关闭状态通知。 */
    fun configure(context: Context, newEnabled: Boolean) {
        appContext = context.applicationContext
        enabled = newEnabled
        prefs(context).edit().putBoolean(KEY_ENABLED, newEnabled).apply()
        ensureRegistered()
        if (enabled) post() else cancel()
    }

    /** 宏会话开始时调用（由 MacroExecutor 主动触发，覆盖后台执行场景）。 */
    fun onSessionStart(context: Context, pluginId: String) {
        appContext = context.applicationContext
        enabled = isEnabled(context)
        if (!enabled) return
        runningPluginId = pluginId
        runningPluginName = resolvePluginName(context, pluginId)
        synchronized(printLines) { printLines.clear() }
        ensureRegistered()
        post()
    }

    /** 悬浮球 / 辅助服务状态变化时刷新通知内容（进程重建后自动从持久化开关恢复）。 */
    fun refreshState(context: Context? = null) {
        val ctx = context?.applicationContext ?: appContext ?: return
        appContext = ctx
        enabled = isEnabled(ctx)
        if (!enabled) return
        ensureRegistered()
        post()
    }

    private fun ensureRegistered() {
        synchronized(this) {
            if (!registered) {
                MacroExecutor.addListener(this)
                registered = true
            }
        }
    }

    // ==== MacroExecutorListener ====

    override fun onMacroStatus(message: String) {
        if (!enabled) return
        val isEnd = message == "任务完成" ||
            message == "任务已停止" ||
            message == "宏已停止" ||
            message.startsWith("任务异常")
        if (isEnd) {
            synchronized(this) {
                runningPluginId = null
                runningPluginName = null
            }
            post()
        }
    }

    override fun onMacroPrint(message: String) {
        if (!enabled) return
        if (message.isBlank()) return
        var newLine = message.trim().take(100)
        if (newLine.length == 100) newLine += "…"
        val shouldPost: Boolean
        synchronized(printLines) {
            printLines.add(newLine)
            if (printLines.size > MAX_PRINT_LINES) {
                printLines.removeAt(0)
            }
            shouldPost = true
        }
        if (shouldPost) post()
    }

    // ==== 通知构建 ====

    private fun resolvePluginName(context: Context, pluginId: String): String? {
        return try {
            val dir = MacroScheduleReceiver.pluginRoot(context, pluginId)
            val file = java.io.File(dir, "manifest.json")
            if (!file.exists()) return null
            val name = JSONObject(file.readText()).optString("name")
            return if (name.isEmpty()) null else name
        } catch (e: Exception) {
            Log.w(TAG, "读取宏名称失败: $pluginId", e)
            null
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "Isolation 状态",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "展示运行状态与宏执行中的 print 输出"
                        setShowBadge(false)
                    }
                )
            }
        }
    }

    private fun post() {
        val ctx = appContext ?: return
        if (!enabled) return
        try {
            ensureChannel(ctx)
            val intent = Intent(ctx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                ctx, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val lines = buildLines(ctx)
            val runningName = synchronized(this) { runningPluginName }
            val title = runningName?.let { "宏运行中：$it" } ?: "Isolation 运行状态"
            val notification: Notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Isolation 状态")
                .setContentText(title)
                .setStyle(NotificationCompat.BigTextStyle().bigText(lines.joinToString("\n")))
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
            val manager = ctx.getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, notification)
            Log.d(TAG, "状态通知已更新")
        } catch (e: Exception) {
            Log.w(TAG, "发布状态通知失败", e)
        }
    }

    private fun buildLines(context: Context): List<String> {
        val lines = mutableListOf<String>()
        val ballRunning = FloatingBallService.getInstance() != null
        lines.add("悬浮球：${if (ballRunning) "运行中" else "未运行"}")
        lines.add("辅助功能：${if (InputAccessibilityService.isReady(context)) "已开启" else "未开启"}")
        MacroScheduler.nextTriggerLabel(context)?.let { lines.add("定时宏：$it") }
        val runningName = synchronized(this) { runningPluginName }
        if (runningName != null) {
            lines.add("宏：运行中《$runningName》")
        } else {
            lines.add("宏：空闲")
        }
        lines.add("")
        lines.add("最近 print 输出：")
        synchronized(printLines) {
            if (printLines.isEmpty()) {
                lines.add("（暂无）")
            } else {
                lines.addAll(printLines)
            }
        }
        return lines
    }

    private fun cancel() {
        val ctx = appContext ?: return
        try {
            ctx.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.w(TAG, "取消状态通知失败", e)
        }
    }
}