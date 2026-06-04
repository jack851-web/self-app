package com.example.selfapp

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.util.Log

/**
 * 无障碍服务 — 按键拦截 + 窗口事件检测
 * 
 * 注意：黑名单检测由 GuardControllerService 的 poller 统一负责，
 * 此服务只负责按键拦截（Home/Back/Recent）和窗口事件拉回。
 */
class KeyInterceptorService : AccessibilityService() {

    private val _handler = Handler(Looper.getMainLooper())

    companion object {
        private const val TAG = "KeyInterceptor"
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
            notificationTimeout = 0
        }
        Log.d(TAG, "无障碍服务已连接")
    }

    // ============================================================
    // 按键拦截
    // ============================================================
    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) return false
        if (!isGuardActive()) return false
        if (event.action != KeyEvent.ACTION_DOWN) return false

        return when (event.keyCode) {
            KeyEvent.KEYCODE_HOME -> {
                Log.d(TAG, "🚫 拦截Home键")
                true
            }
            KeyEvent.KEYCODE_APP_SWITCH -> {
                Log.d(TAG, "🚫 拦截最近任务键")
                true
            }
            KeyEvent.KEYCODE_BACK -> {
                Log.d(TAG, "🚫 拦截返回键")
                true
            }
            else -> false
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 仅记录，不拦截（由 GuardControllerService 统一处理黑名单检测）
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "无障碍服务已销毁")
    }

    private fun isGuardActive(): Boolean {
        return try {
            // 使用加密存储读取守护状态
            EncryptedPrefsManager.getGuardStatePrefs(this@KeyInterceptorService)
                .getBoolean("active", false)
        } catch (_: Exception) { false }
    }
}
