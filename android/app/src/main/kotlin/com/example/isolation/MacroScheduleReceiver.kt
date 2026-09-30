package com.example.isolation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 每日定时触发宏的广播接收器。
 *
 * 到点后加载指定插件的 macro.json，校验辅助功能就绪后交给
 * [InputAccessibilityService.executeMacro] 执行；执行成功后由
 * [MacroScheduler.scheduleNext] 续排明天同一时间。
 */
class MacroScheduleReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "MacroScheduleReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != MacroScheduler.ACTION_MACRO_SCHEDULE) return

        val pluginId = intent.getStringExtra(MacroScheduler.EXTRA_PLUGIN_ID) ?: return
        val macroFile = intent.getStringExtra(MacroScheduler.EXTRA_MACRO_FILE) ?: return
        Log.d(TAG, "定时触发宏: $pluginId/$macroFile")

        // 宏运行中：跳过本次，下一周期正常触发
        if (MacroExecutor.isRunning()) {
            Log.w(TAG, "已有宏在运行，跳过本次定时触发")
            MacroScheduler.scheduleNext(context, intent)
            return
        }

        // 加载目标宏文件
        val macro = loadMacro(context, pluginId, macroFile)
        if (macro == null || macro.steps.isEmpty()) {
            // 宏文件缺失或为空：视为宏已删除，清除定时，不再续排
            Log.w(TAG, "宏文件不存在或为空，清除定时: $pluginId")
            MacroScheduler.cancel(context, pluginId)
            return
        }

        // 校验辅助功能就绪
        val state = InputAccessibilityService.readinessState(context)
        when (state) {
            1 -> {
                Toast.makeText(context, "定时宏未执行：请先开启辅助功能", Toast.LENGTH_SHORT).show()
                return
            }
            2 -> {
                Toast.makeText(context, "定时宏未执行：辅助服务启动中", Toast.LENGTH_SHORT).show()
                return
            }
        }

        val pluginDir = File(File(context.filesDir, "plugins"), pluginId)
        val assetsDir = File(pluginDir, "assets").takeIf { it.exists() }?.absolutePath
        val executed = InputAccessibilityService.executeMacro(
            context, macro.settings, macro.steps, assetsDir, pluginId
        )
        if (executed) {
            // 执行成功后续排明天同一时间（每日重复）
            MacroScheduler.scheduleNext(context, intent)
        }
    }

    private data class MacroFile(
        val settings: Map<String, Any>,
        val steps: List<Map<String, Any>>
    )

    private fun loadMacro(context: Context, pluginId: String, macroFile: String): MacroFile? {
        val file = File(File(context.filesDir, "plugins"), "$pluginId/$macroFile")
        if (!file.exists()) return null
        return try {
            val json = file.readText()
            JSONObject(json).let { obj ->
                val settings = jsonObjectToMap(obj.getJSONObject("settings"))
                val stepsArray = obj.getJSONArray("steps")
                val steps = mutableListOf<Map<String, Any>>()
                for (i in 0 until stepsArray.length()) {
                    steps.add(jsonObjectToMap(stepsArray.getJSONObject(i)))
                }
                MacroFile(settings, steps)
            }
        } catch (e: Exception) {
            // Fallback to legacy list format
            try {
                val array = JSONArray(file.readText())
                val steps = mutableListOf<Map<String, Any>>()
                for (i in 0 until array.length()) {
                    steps.add(jsonObjectToMap(array.getJSONObject(i)))
                }
                MacroFile(emptyMap(), steps)
            } catch (e2: Exception) {
                null
            }
        }
    }

    private fun jsonObjectToMap(obj: JSONObject): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = obj.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: JSONArray): List<Any> {
        val list = mutableListOf<Any>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(when (value) {
                is JSONObject -> jsonObjectToMap(value)
                is JSONArray -> jsonArrayToList(value)
                else -> value
            })
        }
        return list
    }
}