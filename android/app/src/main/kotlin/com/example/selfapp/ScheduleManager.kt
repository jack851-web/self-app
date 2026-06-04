package com.example.selfapp

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.*

object ScheduleManager {

    /** Register start + end alarm for a schedule. */
    fun register(context: Context, id: Long, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, daysOfWeek: Int) {
        if (daysOfWeek == 0) return // 未选择任何日期，不注册闹钟
        cancel(context, id)

        val nextStart = calculateNextTrigger(startHour, startMinute, daysOfWeek)
        if (nextStart == null) return

        // 计算结束时间：基于开始时间偏移，处理跨天场景
        val nextEnd = calculateEndTrigger(nextStart, endHour, endMinute)

        nextStart?.let { setExactAlarm(context, (id * 2).toInt(), it, ScheduleStartReceiver::class.java, id) }
        nextEnd?.let { setExactAlarm(context, (id * 2 + 1).toInt(), it, ScheduleEndReceiver::class.java, id) }
    }

    fun cancel(context: Context, scheduleId: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        listOf(scheduleId * 2, scheduleId * 2 + 1).forEach { req ->
            tryCancel(am, context, req.toInt(), ScheduleStartReceiver::class.java)
            tryCancel(am, context, req.toInt(), ScheduleEndReceiver::class.java)
        }
    }

    /**
     * 计算下一个触发时间点（基于星期掩码）。
     * daysOfWeek: bitmask, bit0=Sun, bit1=Mon, ..., bit6=Sat
     * 
     * 注意：Calendar.DAY_OF_WEEK: 1=Sun, 2=Mon, ..., 7=Sat
     * 转换为我们的格式：(dayOfWeek - 1 + 5) % 7 = (dayOfWeek + 4) % 7
     */
    private fun calculateNextTrigger(hour: Int, minute: Int, daysOfWeek: Int): Long? {
        val now = System.currentTimeMillis()
        val cal = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
        }

        // 如果指定了特定日期，需要找到最近的一个匹配日
        if (daysOfWeek != 0 && daysOfWeek != 0b1111111) {
            // 先检查今天是否匹配且时间未过
            repeat(8) { i ->
                val calendarDow = cal.get(Calendar.DAY_OF_WEEK) // 1-7 (Sun-Sat)
                val ourDow = (calendarDow + 4) % 7  // 转换为 0=Sun ... 6=Sat
                
                if ((daysOfWeek and (1 shl ourDow)) != 0 && cal.timeInMillis > now) {
                    return cal.timeInMillis
                }
                
                // 移动到下一天（如果已经是最后一次循环则返回null）
                if (i < 7) {
                    cal.add(Calendar.DAY_OF_MONTH, 1)
                    // 重置时间为目标时间
                    cal.set(Calendar.HOUR_OF_DAY, hour)
                    cal.set(Calendar.MINUTE, minute)
                }
            }
            return null  // 8天内没有匹配的日期
        }

        // 全选或未设置：如果时间已过则加一天
        if (cal.timeInMillis <= now) cal.add(Calendar.DAY_OF_MONTH, 1)
        return cal.timeInMillis
    }

    /**
     * 基于已知的开始时间计算结束时间。
     * 处理跨天场景：如 22:00 开始、07:00 结束，结束应在次日 07:00。
     */
    private fun calculateEndTrigger(startMs: Long, endHour: Int, endMinute: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = startMs
            set(Calendar.HOUR_OF_DAY, endHour)
            set(Calendar.MINUTE, endMinute)
        }

        // 如果结束时间 <= 开始时间，说明跨天，加一天
        if (cal.timeInMillis <= startMs) {
            cal.add(Calendar.DAY_OF_MONTH, 1)
        }
        return cal.timeInMillis
    }

    private fun setExactAlarm(ctx: Context, requestCode: Int, triggerMs: Long,
                               receiverClass: Class<out BroadcastReceiver>, scheduleId: Long) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(ctx, receiverClass).apply { putExtra("scheduleId", scheduleId) }
        val pi = PendingIntent.getBroadcast(ctx, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pi)
    }

    private fun tryCancel(am: AlarmManager, ctx: Context, req: Int, cls: Class<out BroadcastReceiver>) {
        val pi = PendingIntent.getBroadcast(ctx, req, Intent(ctx, cls),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE) ?: return
        am.cancel(pi); pi.cancel()
    }
}
