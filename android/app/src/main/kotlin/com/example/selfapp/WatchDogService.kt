package com.example.selfapp

import android.app.*
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * 双进程守护服务（运行在独立进程 :watchdog）
 * 
 * 当主进程被杀死时，WatchDog 负责：
 * 1. 重新启动主进程的 GuardControllerService
 * 2. 重新启动 MainActivity
 * 3. 如果无障碍服务停止，尝试重启
 */
class WatchDogService : Service() {

    companion object {
        private const val WATCHDOG_NOTIFICATION_ID = 1002
        private const val CHECK_INTERVAL = 2000L  // 每2秒检查一次
        private const val TAG = "WatchDog"

        fun start(context: Context) {
            val intent = Intent(context, WatchDogService::class.java).apply {
                action = "ACTION_START_WATCH"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, WatchDogService::class.java).apply {
                action = "ACTION_STOP_WATCH"
            }
            context.startService(intent)
        }
    }

    private val _handler = Handler(Looper.getMainLooper())
    private var _watchRunnable: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(WATCHDOG_NOTIFICATION_ID, buildWatchDogNotification())
        startWatching()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "ACTION_START_WATCH" -> startWatching()
            "ACTION_STOP_WATCH" -> {
                stopWatching()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopWatching()
    }

    // ============================================================
    // 核心监控循环
    // ============================================================
    private fun startWatching() {
        stopWatching()
        _watchRunnable = object : Runnable {
            override fun run() {
                try {
                    if (isGuardActive()) {
                        // 检查主进程前台服务是否存活
                        if (!isMainServiceRunning()) {
                            android.util.Log.w(TAG, "⚠️ 主服务已停止，尝试重启...")
                            restartMainService()
                        }

                        // 检查无障碍服务是否存活
                        if (!isAccessibilityRunning()) {
                            android.util.Log.w(TAG, "⚠️ 无障碍服务已停止，尝试重启...")
                            restartAccessibility()
                        }

                        // 检查App是否在前台
                        if (!isAppInForeground()) {
                            android.util.Log.w(TAG, "⚠️ App不在前台，拉回...")
                            bringAppToFront()
                        }
                    } else {
                        // 守护已结束，停止WatchDog
                        stopWatching()
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "WatchDog检查异常", e)
                }
                _handler.postDelayed(this, CHECK_INTERVAL)
            }
        }
        _handler.post(_watchRunnable!!)
        android.util.Log.d(TAG, "🐕 WatchDog 启动 (进程: ${android.os.Process.myPid()})")
    }

    private fun stopWatching() {
        _watchRunnable?.let { _handler.removeCallbacks(it) }
        _watchRunnable = null
    }

    // ============================================================
    // 状态检查方法
    // ============================================================
    private fun isGuardActive(): Boolean {
        return try {
            // 使用加密存储读取守护状态
            EncryptedPrefsManager.getGuardStatePrefs(this@WatchDogService)
                .getBoolean("active", false)
        } catch (_: Exception) { false }
    }

    private fun isMainServiceRunning(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val services = am.getRunningServices(Int.MAX_VALUE)
        return services.any { it.service.className == GuardControllerService::class.java.name }
    }

    private fun isAccessibilityRunning(): Boolean {
        return try {
            val settings = android.provider.Settings.Secure.getString(
                contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            settings?.contains(packageName) == true
        } catch (_: Exception) { false }
    }

    private fun isAppInForeground(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val tasks = am.getRunningTasks(1)
            tasks.isNotEmpty() && tasks[0].topActivity?.packageName == packageName
        } catch (_: Exception) { false }
    }

    // ============================================================
    // 恢复方法
    // ============================================================
    private fun restartMainService() {
        try {
            // 从加密 SharedPreferences 读取剩余时长
            val prefs = EncryptedPrefsManager.getGuardStatePrefs(this@WatchDogService)
            val endAt = prefs.getLong("end_at", 0L)
            val remaining = if (endAt > 0) endAt - System.currentTimeMillis() else 25 * 60_000L
            val durationMs = remaining.coerceAtLeast(60_000L) // 至少1分钟

            GuardControllerService.startManual(this, durationMs)
            android.util.Log.d(TAG, "✅ 主服务已重启，剩余 ${durationMs/60000} 分钟")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "重启主服务失败", e)
        }
    }

    private fun restartAccessibility() {
        try {
            // AccessibilityService 由系统绑定，startService 无效
            // 改为通知用户重新开启（通过通知栏）
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val pi = PendingIntent.getActivity(this, 99, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notif = NotificationCompat.Builder(this, "watchdog-channel")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("守护服务异常")
                .setContentText("无障碍服务已断开，点击重新开启")
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            nm.notify(1003, notif)
            android.util.Log.d(TAG, "✅ 已发送无障碍服务恢复通知")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "重启无障碍服务失败", e)
        }
    }

    private fun bringAppToFront() {
        try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
            }
            if (intent != null) startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "拉回前台失败", e)
        }
    }

    // ============================================================
    // 通知
    // ============================================================
    private fun buildWatchDogNotification(): Notification {
        createWatchDogChannel()
        return NotificationCompat.Builder(this, "watchdog-channel")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle("守护服务")
            .setContentText("后台保护运行中")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
    }

    private fun createWatchDogChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "watchdog-channel", "守护保护",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "双进程守护常驻通知"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }
}
