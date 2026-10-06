package com.qangxing.isolation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用升级后恢复每日定时启动宏的注册。
 *
 * AlarmManager 的 RTC 闹钟在系统重启后不会保留，需要重新注册。
 * ACTION_MY_PACKAGE_REPLACED 仅发送给本应用，应用升级后同样需要恢复闹钟。
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            MacroScheduler.restoreAll(context)
            Log.d(TAG, "恢复定时完成: ${intent.action}")
        }
    }
}