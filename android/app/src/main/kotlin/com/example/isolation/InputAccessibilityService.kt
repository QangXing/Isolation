package com.example.isolation

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

class InputAccessibilityService : AccessibilityService() {
    companion object {
        private var instance: InputAccessibilityService? = null

        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val serviceName = "${context.packageName}/${InputAccessibilityService::class.java.canonicalName}"
            return enabledServices.contains(serviceName)
        }

        fun showInputMethod(context: Context) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectKey(context: Context, key: String) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                val newText = currentText + key
                val arguments = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        newText
                    )
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }

        fun injectBackspace(context: Context) {
            val service = instance
            if (service == null) {
                Toast.makeText(context, "请先开启辅助功能权限", Toast.LENGTH_SHORT).show()
                return
            }
            val node = service.findFocusedInputNode()
            if (node != null) {
                val currentText = node.text?.toString() ?: ""
                if (currentText.isNotEmpty()) {
                    val newText = currentText.substring(0, currentText.length - 1)
                    val arguments = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            newText
                        )
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                }
            } else {
                Toast.makeText(context, "未找到输入框", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op
    }

    override fun onInterrupt() {
        instance = null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    private fun findFocusedInputNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
    }
}
