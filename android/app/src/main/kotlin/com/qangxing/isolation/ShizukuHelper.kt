package com.qangxing.isolation

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuProvider

/**
 * Shizuku 状态检测与授权辅助类。
 *
 * 负责：
 * - 检测 Shizuku 应用是否安装、服务是否运行；
 * - 检查/请求 Shizuku 授权；
 * - 在授权成功后通过 Binder 以 shell 身份执行高权限命令。
 *
 * 注意：Shizuku 本身不等于 root。通过 Shizuku 执行 `getevent` 读取系统输入事件
 * 仍然依赖设备是否允许 shell/应用访问 /dev/input/event*。在部分系统上该能力
 * 需要 root 或特殊 SELinux 策略，本类仅负责把状态暴露给上层，方便降级。
 */
object ShizukuHelper {

    private const val TAG = "ShizukuHelper"
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    /** Shizuku 授权请求码，仅用于内部 listener 区分。 */
    private const val REQ_PERMISSION = 10001

    /** 0=就绪；1=未安装；2=服务未运行；3=未授权 */
    enum class State(val code: Int) {
        READY(0),
        NOT_INSTALLED(1),
        SERVER_NOT_RUNNING(2),
        NOT_AUTHORIZED(3)
    }

    interface StateListener {
        fun onShizukuStateChanged(state: State)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val binderListeners = mutableListOf<() -> Unit>()
    private val stateListeners = mutableListOf<StateListener>()

    @Volatile
    private var lastKnownState: State? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        mainHandler.post { notifyBinderReceived() }
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        mainHandler.post { notifyStateChanged() }
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == REQ_PERMISSION) {
                mainHandler.post { notifyStateChanged() }
            }
        }

    init {
        Shizuku.addBinderReceivedListener(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionListener)
    }

    /** 当前 Shizuku 状态（是否安装/运行/授权）。 */
    fun currentState(context: Context): State {
        if (!isShizukuInstalled(context)) return State.NOT_INSTALLED
        if (!Shizuku.pingBinder()) return State.SERVER_NOT_RUNNING
        return if (hasPermission()) State.READY else State.NOT_AUTHORIZED
    }

    /** Shizuku 应用是否已安装。 */
    fun isShizukuInstalled(context: Context): Boolean {
        return try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    /** Shizuku 服务是否运行（Binder 是否连上）。 */
    fun isServerRunning(): Boolean = Shizuku.pingBinder()

    /** 是否已拿到 Shizuku 授权。 */
    fun hasPermission(): Boolean {
        return try {
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    /** 请求 Shizuku 授权。需要在 Activity 或 Fragment 中调用。 */
    fun requestPermission() {
        try {
            Shizuku.requestPermission(REQ_PERMISSION)
        } catch (e: Exception) {
            Log.w(TAG, "请求 Shizuku 授权失败", e)
        }
    }

    /** 跳转到 Shizuku 应用或下载页。 */
    fun openShizuku(context: Context) {
        val intent = if (isShizukuInstalled(context)) {
            context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
        } else null
        val finalIntent = intent ?: Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://shizuku.rikka.app/")
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        try {
            context.startActivity(finalIntent)
        } catch (e: Exception) {
            Log.e(TAG, "打开 Shizuku 失败", e)
        }
    }

    /** 注册状态监听器。 */
    fun addStateListener(listener: StateListener) {
        if (!stateListeners.contains(listener)) stateListeners.add(listener)
        // 立即回调一次当前状态
        listener.onShizukuStateChanged(currentStateSafely())
    }

    /** 移除状态监听器。 */
    fun removeStateListener(listener: StateListener) {
        stateListeners.remove(listener)
    }

    /** 注册一次性 Binder 就绪回调（授权成功后触发）。 */
    fun onBinderReceived(action: () -> Unit) {
        if (Shizuku.pingBinder()) {
            mainHandler.post(action)
            return
        }
        binderListeners.add(action)
    }

    private fun notifyBinderReceived() {
        notifyStateChanged()
        val copy = binderListeners.toList()
        binderListeners.clear()
        copy.forEach { mainHandler.post(it) }
    }

    private fun notifyStateChanged() {
        val state = currentStateSafely()
        lastKnownState = state
        stateListeners.toList().forEach { it.onShizukuStateChanged(state) }
    }

    private fun currentStateSafely(): State {
        return try {
            // ShizukuProvider 在清单中自动初始化；若 isInstalled 与 pingBinder 都 true 则 READY
            if (!Shizuku.pingBinder()) State.SERVER_NOT_RUNNING
            else if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) State.NOT_AUTHORIZED
            else State.READY
        } catch (e: Exception) {
            State.SERVER_NOT_RUNNING
        }
    }

    /** 友好的错误提示，返回是否可继续。 */
    fun toastIfNotReady(context: Context): Boolean {
        val state = currentState(context)
        val message = when (state) {
            State.READY -> null
            State.NOT_INSTALLED -> "请先安装 Shizuku"
            State.SERVER_NOT_RUNNING -> "请先启动 Shizuku 服务"
            State.NOT_AUTHORIZED -> "请在 Shizuku 中授予本应用权限"
        }
        message?.let { Toast.makeText(context, it, Toast.LENGTH_SHORT).show() }
        return state == State.READY
    }
}
