package com.example.selfapp

import android.app.*
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NativeChannel : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.selfapp/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsageStatsPermission" -> result.success(checkUsageStats())
            "requestUsageStatsPermission" -> { openUsageStatsSettings(); result.success(null) }
            "hasOverlayPermission" -> result.success(checkOverlay())
            "requestOverlayPermission" -> { openOverlaySettings(); result.success(null) }
            "hasAccessibilityPermission" -> result.success(checkAccessibility())
            "requestAccessibilityPermission" -> { openAccessibilitySettings(); result.success(null) }
            "startManualGuard" -> {
                val minutes = call.argument<Int>("durationMinutes") ?: 25
                GuardControllerService.startManual(context, minutes * 60_000L)
                result.success(null)
            }
            "stopGuard" -> {
                GuardControllerService.stop(context)
                result.success(null)
            }
            "registerSchedule" -> {
                val schedule = call.argument<Map<String, Any>>("schedule") ?: emptyMap()
                val id = (schedule["id"] as? Number)?.toLong() ?: System.currentTimeMillis()
                val startHour = (schedule["startHour"] as? Number)?.toInt() ?: 22
                val startMinute = (schedule["startMinute"] as? Number)?.toInt() ?: 0
                val endHour = (schedule["endHour"] as? Number)?.toInt() ?: 7
                val endMinute = (schedule["endMinute"] as? Number)?.toInt() ?: 0
                val daysOfWeek = (schedule["daysOfWeek"] as? Number)?.toInt() ?: 127
                val enabled = schedule["enabled"] as? Boolean ?: true

                // 持久化到 Android 端 schedules SharedPreferences（供开机恢复使用）
                persistSchedule(context, id, startHour, startMinute, endHour, endMinute, daysOfWeek, enabled)

                if (enabled) {
                    ScheduleManager.register(context, id, startHour, startMinute, endHour, endMinute, daysOfWeek)
                } else {
                    ScheduleManager.cancel(context, id)
                }
                result.success(null)
            }
            "cancelSchedule" -> {
                val id = call.argument<Int>("scheduleId") ?: -1
                ScheduleManager.cancel(context, id.toLong())
                removePersistedSchedule(context, id.toLong())
                result.success(null)
            }
            "getInstalledApps" -> {
                val query = call.argument<String>("query") ?: ""
                val apps = getInstalledApps(query)
                result.success(mapOf("apps" to apps))
            }
            "syncBlocklist" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                saveBlocklist(context, packages)
                android.util.Log.d("NativeChannel", "同步黑名单: ${packages.size} 个应用")
                result.success(null)
            }
            "bringToFront" -> {
                // 将自身 Activity 拉回前台
                val pm = context.packageManager
                val intent = pm.getLaunchIntentForPackage(context.packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                }
                if (intent != null) context.startActivity(intent)
                result.success(null)
            }
            // === 设备管理员 ===
            "hasDeviceAdmin" -> {
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                val admin = ComponentName(context, SelfAppDeviceAdmin::class.java)
                result.success(dpm?.isAdminActive(admin) == true)
            }
            "requestDeviceAdmin" -> {
                try {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(
                            DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                            ComponentName(context, SelfAppDeviceAdmin::class.java)
                        )
                        putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "设备管理员权限用于防止在自律模式下被强制停止或卸载"
                        )
                    }
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("REQUEST_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    // === Permission Checks ===
    private fun checkUsageStats(): Boolean {
        val usageStats = context.getSystemService(Context.USAGE_STATS_SERVICE) as? android.app.usage.UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usageStats?.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_BEST, now - 1000, now)
        return stats != null && stats.isNotEmpty()
    }

    private fun checkOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    private fun checkAccessibility(): Boolean {
        val service = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        val enabledServices = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return enabledServices?.contains(context.packageName) == true
    }

    // === Open Settings ===
    private fun openUsageStatsSettings() {
        context.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun openOverlaySettings() {
        context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
            data = android.net.Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }

    private fun openAccessibilitySettings() {
        context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // === App List ===
    private fun getInstalledApps(query: String): List<Map<String, String>> {
        val pm = context.packageManager
        val apps = mutableListOf<Map<String, String>>()
        
        try {
            val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
            
            android.util.Log.d("NativeChannel", "总安装应用数: ${installedApps.size}")
            
            // 过滤：只显示用户安装的应用（非系统应用或已更新的系统应用）
            val filteredApps = installedApps.filter { info: ApplicationInfo ->
                (info.flags and ApplicationInfo.FLAG_SYSTEM) == 0 ||
                info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
            }
            
            android.util.Log.d("NativeChannel", "过滤后用户应用数: ${filteredApps.size}")
            
            for (info in filteredApps) {
                try {
                    val label = pm.getApplicationLabel(info).toString()
                    val entry = mapOf(
                        "packageName" to info.packageName,
                        "label" to label
                    )
                    
                    // 如果有搜索词，进行过滤
                    if (query.isEmpty() || 
                        label.contains(query, ignoreCase = true) || 
                        info.packageName.contains(query, ignoreCase = true)) {
                        apps.add(entry)
                    }
                } catch (e: Exception) {
                    android.util.Log.w("NativeChannel", "跳过应用 ${info.packageName}: ${e.message}")
                }
            }
            
            apps.sortBy { it["label"] ?: "" }
            android.util.Log.d("NativeChannel", "返回应用数: ${apps.size}")
            
        } catch (e: SecurityException) {
            android.util.Log.e("NativeChannel", "❌ 安全异常 - 可能缺少 QUERY_ALL_PACKAGES 权限", e)
            throw e  // 重新抛出让Flutter端处理
        } catch (e: Exception) {
            android.util.Log.e("NativeChannel", "❌ 获取应用列表失败", e)
            throw e  // 重新抛出让Flutter端处理
        }
        
        return apps
    }

    // === Schedule Persistence (for boot recovery) ===

    private fun persistSchedule(ctx: Context, id: Long, startHour: Int, startMinute: Int,
                                 endHour: Int, endMinute: Int, daysOfWeek: Int, enabled: Boolean) {
        // 使用加密存储保护定时计划数据
        val prefs = EncryptedPrefsManager.getSchedulesPrefs(ctx)
        val raw = prefs.getString("guard_schedules", "[]")!!
        val arr = org.json.JSONArray(raw)
        // 移除同 id 旧记录
        val newArr = org.json.JSONArray()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            if (obj.optLong("id") != id) newArr.put(obj)
        }
        // 添加新记录
        val newObj = org.json.JSONObject().apply {
            put("id", id)
            put("startHour", startHour)
            put("startMinute", startMinute)
            put("endHour", endHour)
            put("endMinute", endMinute)
            put("daysOfWeek", daysOfWeek)
            put("enabled", enabled)
        }
        newArr.put(newObj)
        prefs.edit().putString("guard_schedules", newArr.toString()).apply()
    }

    private fun removePersistedSchedule(ctx: Context, id: Long) {
        // 使用加密存储
        val prefs = EncryptedPrefsManager.getSchedulesPrefs(ctx)
        val raw = prefs.getString("guard_schedules", "[]")!!
        val arr = org.json.JSONArray(raw)
        val newArr = org.json.JSONArray()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            if (obj.optLong("id") != id) newArr.put(obj)
        }
        prefs.edit().putString("guard_schedules", newArr.toString()).apply()
    }

    // === Blocklist Persistence ===

    private fun saveBlocklist(ctx: Context, packages: List<String>) {
        // 使用加密存储保护黑名单数据
        val prefs = EncryptedPrefsManager.getBlocklistPrefs(ctx)
        val set = packages.toSet()
        prefs.edit().putStringSet("packages", set).apply()
    }

    fun getBlocklist(ctx: Context): Set<String> {
        return try {
            // 使用加密存储
            EncryptedPrefsManager.getBlocklistPrefs(ctx)
                .getStringSet("packages", emptySet()) ?: emptySet()
        } catch (_: Exception) {
            emptySet()
        }
    }
}
