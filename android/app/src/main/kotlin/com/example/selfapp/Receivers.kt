package com.example.selfapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

class SessionEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        GuardControllerService.stop(context)
    }
}

class ScheduleStartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val scheduleId = intent?.getLongExtra("scheduleId", -1L) ?: -1L
        if (scheduleId >= 0) GuardControllerService.startScheduled(context, scheduleId)
    }
}

class ScheduleEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        GuardControllerService.stop(context)
    }
}

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        // 从 SharedPreferences 读取已保存的定时计划，重新注册闹钟
        try {
            val prefs = context.getSharedPreferences("schedules", Context.MODE_PRIVATE)
            val raw = prefs.getString("guard_schedules", null) ?: return
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val enabled = obj.optBoolean("enabled", false)
                if (!enabled) continue
                val id = obj.optLong("id", System.currentTimeMillis())
                val startHour = obj.getInt("startHour")
                val startMinute = obj.getInt("startMinute")
                val endHour = obj.getInt("endHour")
                val endMinute = obj.getInt("endMinute")
                val daysOfWeek = obj.getInt("daysOfWeek")
                ScheduleManager.register(context, id, startHour, startMinute, endHour, endMinute, daysOfWeek)
            }

            // 如果守护状态为 active（异常关机导致未正常停止），则清除守护状态
            // 使用加密存储
            val guardPrefs = EncryptedPrefsManager.getGuardStatePrefs(context)
            if (guardPrefs.getBoolean("active", false)) {
                guardPrefs.edit().apply {
                    putBoolean("active", false)
                    remove("start_at")
                    remove("end_at")
                    remove("trigger_type")
                    remove("schedule_id")
                    apply()
                }
            }
        } catch (_: Exception) {
            // JSON 解析失败时静默忽略
        }
    }
}
