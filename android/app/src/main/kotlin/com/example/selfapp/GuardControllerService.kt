package com.example.selfapp

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import java.util.*

class GuardControllerService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1001
        private var _heartbeatRunnable: Runnable? = null

        fun startManual(context: Context, durationMs: Long) {
            Intent(context, GuardControllerService::class.java).also { intent ->
                intent.action = "ACTION_START_MANUAL"
                intent.putExtra("duration_ms", durationMs)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun startScheduled(context: Context, scheduleId: Long) {
            Intent(context, GuardControllerService::class.java).also { intent ->
                intent.action = "ACTION_START_SCHEDULED"
                intent.putExtra("schedule_id", scheduleId)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun stop(context: Context) {
            Intent(context, GuardControllerService::class.java).also {
                it.action = "ACTION_STOP"
                context.startService(it)
            }
        }
    }

    private val _handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification("守护服务", "准备中..."))
        // 启动心跳保活
        startHeartbeat()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "ACTION_START_MANUAL" -> handleStartManual(intent.getLongExtra("duration_ms", 25 * 60_000L))
            "ACTION_START_SCHEDULED" -> handleStartScheduled(intent.getLongExtra("schedule_id", -1))
            "ACTION_STOP" -> handleStop()
            else -> {
                // 未知或null action，停止服务避免空转
                android.util.Log.w("GuardController", "收到未知action: ${intent?.action}, 停止服务")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // 使用 START_REDELIVER_INTENT：系统杀死后会重新传递最后一个 Intent 重启服务
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAppPoller()
        stopHeartbeat()
        android.util.Log.d("GuardController", "服务被销毁")
    }

    private fun handleStartManual(durationMs: Long) {
        val now = System.currentTimeMillis()
        val endAt = now + durationMs

        // Save guard state to EncryptedSharedPreferences
        EncryptedPrefsManager.getGuardStatePrefs(this@GuardControllerService).edit().apply {
            putBoolean("active", true)
            putLong("start_at", now)
            putLong("end_at", endAt)
            putString("trigger_type", "MANUAL")
            apply()
        }

        // Register end alarm
        registerEndAlarm(endAt)

        // 启动前台应用轮询检测
        startAppPoller()

        // 启动双进程WatchDog
        WatchDogService.start(this)

        // Update notification
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification("手动守护进行中", "受保护的应用已锁定"))

        // Start lock screen activity via Flutter navigation
        // The Flutter side will navigate to /lock route
    }

    private fun handleStartScheduled(scheduleId: Long) {
        val now = System.currentTimeMillis()
        // 使用加密存储
        EncryptedPrefsManager.getGuardStatePrefs(this@GuardControllerService).edit().apply {
            putBoolean("active", true)
            putLong("start_at", now)
            putString("trigger_type", "SCHEDULED")
            putLong("schedule_id", scheduleId)
            apply()
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification("定时守护中", "受保护的应用已锁定"))
    }

    private fun handleStop() {
        cancelEndAlarm()
        // 停止前台应用轮询
        stopAppPoller()
        // 停止双进程WatchDog
        WatchDogService.stop(this)
        // 使用加密存储清除守护状态
        EncryptedPrefsManager.getGuardStatePrefs(this@GuardControllerService).edit().apply {
            putBoolean("active", false)
            remove("start_at")
            remove("end_at")
            remove("trigger_type")
            remove("schedule_id")
            apply()
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun registerEndAlarm(endAt: Long) {
        try {
            val am = getSystemService(ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, SessionEndReceiver::class.java).apply { action = "ACTION_SESSION_END" }
            val pi = PendingIntent.getBroadcast(this, 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            
            // Android 12+ 需要精确闹钟权限，降级为非精确闹钟
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                android.util.Log.w("GuardController", "无精确闹钟权限，使用非精确闹钟")
                am.set(AlarmManager.RTC_WAKEUP, endAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, pi)
            }
        } catch (e: SecurityException) {
            android.util.Log.e("GuardController", "注册结束闹钟失败（可能缺少SCHEDULE_EXACT_ALARM权限），将使用Timer作为备用", e)
            // 备用方案：使用 Handler 延迟执行
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                handleStop()
            }, endAt - System.currentTimeMillis())
        } catch (e: Exception) {
            android.util.Log.e("GuardController", "注册结束闹钟失败", e)
        }
    }

    private fun cancelEndAlarm() {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, SessionEndReceiver::class.java).apply { action = "ACTION_SESSION_END" }
        val pi = PendingIntent.getBroadcast(this, 1, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE) ?: return
        am.cancel(pi)
        pi.cancel()
    }

    override fun onBind(intent: Intent?) = null

    // === 前台应用轮询检测（核心拦截逻辑） ===
    private var _appPollerRunnable: Runnable? = null
    private var _lastDetectedPkg: String? = null
    private var _detectCooldown = 0L

    private fun startAppPoller() {
        stopAppPoller()
        android.util.Log.d("GuardController", "▶ 启动前台应用轮询 (500ms)")
        _appPollerRunnable = object : Runnable {
            private var _cycle = 0
            override fun run() {
                try {
                    _cycle++
                    if (!isGuardActive()) {
                        stopAppPoller()
                        return@run
                    }

                    // 加载黑名单（使用加密存储）
                    val blocklist = EncryptedPrefsManager.getBlocklistPrefs(this@GuardControllerService)
                        .getStringSet("packages", emptySet()) ?: emptySet()

                    // 每2秒检测一次
                    if (_cycle % 4 == 0) {
                        val fgPkg = detectForegroundApp()
                        if (fgPkg != null && fgPkg != packageName && blocklist.contains(fgPkg)) {
                            val now = System.currentTimeMillis()
                            if (fgPkg != _lastDetectedPkg || now - _detectCooldown > 5000) {
                                _lastDetectedPkg = fgPkg
                                _detectCooldown = now
                                android.util.Log.d("GuardController", "🚫 检测到黑名单应用: $fgPkg, 启动覆盖层")
                                LockOverlayActivity.start(this@GuardControllerService, fgPkg)
                            }
                        }
                    }
                    // 每30秒输出心跳
                    if (_cycle % 60 == 0) {
                        android.util.Log.d("GuardController", "轮询心跳: cycle=$_cycle active=${isGuardActive()} blocklist.size=${blocklist.size}")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("GuardController", "轮询异常: ${e.message}")
                }
                _handler.postDelayed(this, 500L)
            }
        }
        _handler.postDelayed(_appPollerRunnable!!, 2000) // 首次延迟2秒
    }

    private fun stopAppPoller() {
        _appPollerRunnable?.let { _handler.removeCallbacks(it) }
        _appPollerRunnable = null
        android.util.Log.d("GuardController", "■ 停止前台应用轮询")
    }

    private fun detectForegroundApp(): String? {
        // 策略1: ActivityManager.getRunningAppProcesses
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (proc in am.runningAppProcesses) {
                if (proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                    || proc.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE) {
                    return proc.processName
                }
            }
        } catch (_: Exception) {}

        // 策略2: UsageStatsManager
        try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
            val now = System.currentTimeMillis()
            val stats = usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_BEST, now - 3000, now)
            stats?.maxByOrNull { it.lastTimeUsed }?.packageName?.let { return it }
        } catch (_: Exception) {}

        return null
    }

    private fun isGuardActive(): Boolean {
        return try {
            // 使用加密存储读取守护状态
            EncryptedPrefsManager.getGuardStatePrefs(this@GuardControllerService)
                .getBoolean("active", false)
        } catch (_: Exception) { false }
    }

    private fun buildNotification(title: String, body: String): Notification {
        createNotificationChannel()
        
        val builder = NotificationCompat.Builder(this, "guard-channel")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)  // 最高优先级
            .setCategory(NotificationCompat.CATEGORY_CALL)  // 使用通话类别提高重要性
            .setShowWhen(false)
        
        // Android 10+：全屏 Intent 防止被系统杀死
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val fullScreenIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("from_notification", true)
            }
            if (fullScreenIntent != null) {
                builder.setFullScreenIntent(
                    PendingIntent.getActivity(this, 0, fullScreenIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
                    true
                )
            }
        }
        
        return builder.build()
    }

    // === 心跳保活 ===
    private fun startHeartbeat() {
        stopHeartbeat()
        _heartbeatRunnable = object : Runnable {
            override fun run() {
                try {
                    // 更新通知保持前台服务活跃（使用加密存储）
                    val prefs = EncryptedPrefsManager.getGuardStatePrefs(this@GuardControllerService)
                    if (prefs.getBoolean("active", false)) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        nm.notify(NOTIFICATION_ID, buildNotification(
                            "守护进行中",
                            "自律模式已开启 - 请勿关闭此通知"
                        ))
                    }
                } catch (e: Exception) {
                    android.util.Log.e("GuardController", "心跳更新失败", e)
                }
                _handler.postDelayed(this, 30_000L)  // 每30秒心跳一次
            }
        }
        _handler.post(_heartbeatRunnable!!)
    }

    private fun stopHeartbeat() {
        _heartbeatRunnable?.let { _handler.removeCallbacks(it) }
        _heartbeatRunnable = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "guard-channel", "守护服务", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "守护模式运行时的常驻通知" }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(channel)
        }
    }
}
