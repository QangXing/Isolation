package com.example.isolation

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 每日定时启动宏的注册 / 取消 / 续排与持久化。
 *
 * - 使用 AlarmManager 精确闹钟（Android 12+ 无精确闹钟权限时回退为非精确）。
 * - 配置保存在 SharedPreferences，开机后由 BootReceiver 调用 [restoreAll] 恢复。
 */
object MacroScheduler {

    const val ACTION_MACRO_SCHEDULE = "com.example.isolation.MACRO_SCHEDULE"

    private const val TAG = "MacroScheduler"
    private const val PREF_NAME = "isolation_macro_schedules"
    private const val KEY_SCHEDULES = "schedules"

    // Intent extras
    const val EXTRA_PLUGIN_ID = "pluginId"
    const val EXTRA_MACRO_FILE = "macroFile"
    const val EXTRA_HOUR = "hour"
    const val EXTRA_MINUTE = "minute"

    data class ScheduleConfig(
        val pluginId: String,
        val macroFile: String,
        val hour: Int,
        val minute: Int,
    )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    /** 保存配置并注册下一次闹钟。 */
    fun schedule(context: Context, pluginId: String, macroFile: String, hour: Int, minute: Int) {
        val config = ScheduleConfig(
            pluginId,
            macroFile,
            hour.coerceIn(0, 23),
            minute.coerceIn(0, 59),
        )
        saveConfig(context, config)
        registerAlarm(context, config)
        Log.d(TAG, "已注册定时: $config")
    }

    /** 取消某宏的定时并清除配置。 */
    fun cancel(context: Context, pluginId: String) {
        cancelAlarm(context, pluginId)
        removeConfig(context, pluginId)
        Log.d(TAG, "已取消定时: $pluginId")
    }

    /**
     * 闹钟触发后延续到明天同一时间。
     * 返回 false 表示配置已被清除（宏已删除），不应再续排。
     */
    fun scheduleNext(context: Context, intent: Intent): Boolean {
        val pluginId = intent.getStringExtra(EXTRA_PLUGIN_ID) ?: return false
        val config = readConfigs(context).firstOrNull { it.pluginId == pluginId } ?: return false
        registerAlarm(context, config)
        return true
    }

    /** 开机 / 应用升级后恢复所有已保存的定时。 */
    fun restoreAll(context: Context) {
        readConfigs(context).forEach { registerAlarm(context, it) }
        Log.d(TAG, "已恢复定时: ${readConfigs(context).size} 条")
    }

    private fun registerAlarm(context: Context, config: ScheduleConfig) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = nextTriggerAt(config.hour, config.minute)
        val pendingIntent = buildPendingIntent(context, config)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (useExactAlarm(context)) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent
                )
            }
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    private fun cancelAlarm(context: Context, pluginId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val intent = Intent(context, MacroScheduleReceiver::class.java).apply {
            action = ACTION_MACRO_SCHEDULE
        }
        val pendingIntent = PendingIntent.getBroadcast(context, pluginId.hashCode(), intent, flags)
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun buildPendingIntent(context: Context, config: ScheduleConfig): PendingIntent {
        val intent = Intent(context, MacroScheduleReceiver::class.java).apply {
            action = ACTION_MACRO_SCHEDULE
            putExtra(EXTRA_PLUGIN_ID, config.pluginId)
            putExtra(EXTRA_MACRO_FILE, config.macroFile)
            putExtra(EXTRA_HOUR, config.hour)
            putExtra(EXTRA_MINUTE, config.minute)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, config.pluginId.hashCode(), intent, flags)
    }

    private fun nextTriggerAt(hour: Int, minute: Int): Long {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (target.timeInMillis <= now.timeInMillis) {
            target.add(Calendar.DAY_OF_YEAR, 1)
        }
        return target.timeInMillis
    }

    /** Android 12+ 需要 SCHEDULE_EXACT_ALARM 权限才能使用精确闹钟。 */
    private fun useExactAlarm(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarmManager.canScheduleExactAlarms()
    }

    // === 配置持久化 ===

    private fun saveConfig(context: Context, config: ScheduleConfig) {
        val map = readConfigs(context).associateBy { it.pluginId }.toMutableMap()
        map[config.pluginId] = config
        writeConfigs(context, map.values.sortedBy { it.pluginId })
    }

    private fun removeConfig(context: Context, pluginId: String) {
        writeConfigs(context, readConfigs(context).filterNot { it.pluginId == pluginId })
    }

    private fun readConfigs(context: Context): List<ScheduleConfig> {
        val raw = prefs(context).getString(KEY_SCHEDULES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.getJSONObject(i)
                val pluginId = obj.optString("pluginId")
                val macroFile = obj.optString("macroFile")
                if (pluginId.isEmpty() || macroFile.isEmpty()) {
                    null
                } else {
                    ScheduleConfig(
                        pluginId,
                        macroFile,
                        obj.optInt("hour", 0),
                        obj.optInt("minute", 0),
                    )
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun writeConfigs(context: Context, configs: List<ScheduleConfig>) {
        val array = JSONArray()
        configs.forEach {
            array.put(JSONObject().apply {
                put("pluginId", it.pluginId)
                put("macroFile", it.macroFile)
                put("hour", it.hour)
                put("minute", it.minute)
            })
        }
        prefs(context).edit().putString(KEY_SCHEDULES, array.toString()).apply()
    }
}