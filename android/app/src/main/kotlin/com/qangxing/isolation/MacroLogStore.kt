package com.qangxing.isolation

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 宏执行日志捕获与持久化。
 *
 * - 作为 [MacroExecutorListener] 注册到 [MacroExecutor]，捕获每次执行的
 *   `print` 输出与 `onMacroStatus` 状态文本。
 * - 按宏（pluginId）分文件存储于 `<filesDir>/macro_logs/<pluginId>.json`。
 * - 记录规则：
 *   - `print`：始终记录。
 *   - 生命周期状态（开始执行 / 任务完成 / 任务已停止 / 宏已停止 / 任务异常）：始终记录。
 *   - 其它状态（调试模式步骤等）：仅当该宏开启调试模式时记录。
 */
object MacroLogStore : MacroExecutorListener {

    private const val TAG = "MacroLogStore"
    private const val LOG_DIR = "macro_logs"
    private const val MAX_LOG_ENTRIES = 300

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var sessionPluginId: String? = null

    @Volatile
    private var sessionDebugMode = false

    private var registered = false

    /** 生命周期状态关键词：始终记录，作为日志上下文锚点。 */
    private val lifecycleStatuses = setOf(
        "开始执行",
        "任务完成",
        "任务已停止",
        "宏已停止",
    )

    private fun isLifecycle(message: String): Boolean =
        lifecycleStatuses.contains(message) || message.startsWith("任务异常")

    /**
     * 一次宏执行会话开始时调用。
     * @param context 用于定位文件目录（传入 applicationContext 即可）
     * @param pluginId 当前执行的宏 id；为 null 时不记录（兼容未传 id 的旧调用路径）
     * @param debugMode 该宏是否开启调试模式
     */
    fun onSessionStart(context: Context, pluginId: String?, debugMode: Boolean) {
        appContext = context.applicationContext
        sessionPluginId = pluginId
        sessionDebugMode = debugMode
        synchronized(this) {
            if (!registered) {
                MacroExecutor.addListener(this)
                registered = true
            }
        }
    }

    // ==== MacroExecutorListener ====

    override fun onMacroStatus(message: String) {
        if (sessionPluginId == null) return
        if (!sessionDebugMode && !isLifecycle(message)) return
        append("status", message)
    }

    override fun onMacroPrint(message: String) {
        if (sessionPluginId == null) return
        if (message.isBlank()) return
        append("print", message)
    }

    // ==== 查询 / 清空 ====

    /** 读取某宏的日志（时间升序）。文件不存在或损坏时返回空列表。 */
    fun getLogs(context: Context, pluginId: String): List<Map<String, Any>> {
        val file = logFile(context, pluginId)
        if (!file.exists()) return emptyList()
        return try {
            val array = JSONArray(file.readText())
            val list = mutableListOf<Map<String, Any>>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                list.add(
                    mapOf(
                        "timeMillis" to obj.optLong("timeMillis", 0L),
                        "type" to obj.optString("type", "status"),
                        "message" to obj.optString("message", ""),
                    )
                )
            }
            list
        } catch (e: Exception) {
            Log.e(TAG, "读取日志失败: $pluginId", e)
            emptyList()
        }
    }

    /** 清空某宏的日志。 */
    fun clearLogs(context: Context, pluginId: String) {
        val file = logFile(context, pluginId)
        if (file.exists()) file.delete()
    }

    // ==== 持久化 ====

    private fun append(type: String, message: String) {
        val ctx = appContext ?: return
        val pluginId = sessionPluginId ?: return
        try {
            val file = logFile(ctx, pluginId)
            val logs = getEntries(file).toMutableList()
            logs.add(
                JSONObject().apply {
                    put("timeMillis", System.currentTimeMillis())
                    put("type", type)
                    put("message", message)
                }
            )
            val trimmed = if (logs.size > MAX_LOG_ENTRIES) {
                logs.takeLast(MAX_LOG_ENTRIES)
            } else {
                logs
            }
            file.parentFile?.mkdirs()
            file.writeText(JSONArray(trimmed).toString())
        } catch (e: Exception) {
            Log.e(TAG, "写入日志失败: $pluginId", e)
        }
    }

    private fun logFile(context: Context, pluginId: String): File =
        File(File(context.filesDir, LOG_DIR), "$pluginId.json")

    private fun getEntries(file: File): List<JSONObject> {
        if (!file.exists()) return emptyList()
        return try {
            val array = JSONArray(file.readText())
            val list = mutableListOf<JSONObject>()
            for (i in 0 until array.length()) {
                list.add(array.getJSONObject(i))
            }
            list
        } catch (e: Exception) {
            emptyList()
        }
    }
}