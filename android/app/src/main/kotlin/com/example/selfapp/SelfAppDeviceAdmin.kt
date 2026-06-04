package com.example.selfapp

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

class SelfAppDeviceAdmin : DeviceAdminReceiver() {

    companion object {
        private const val TAG = "DeviceAdmin"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "✅ 设备管理员已激活")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "⚠️ 设备管理员已禁用")
        // 如果守护正在运行，重新请求激活
        if (isGuardActive(context)) {
            Log.d(TAG, "守护仍在运行，尝试重新激活设备管理员")
            requestActivation(context)
        }
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence? {
        // 当用户尝试禁用设备管理员时，显示警告
        return "警告：禁用设备管理员将导致自律功能失效！\n\n如果您正在使用自律模式，请先结束守护后再操作。"
    }

    /** 检查守护是否激活 */
    private fun isGuardActive(context: Context): Boolean {
        return try {
            // 使用加密存储读取守护状态
            EncryptedPrefsManager.getGuardStatePrefs(context)
                .getBoolean("active", false)
        } catch (_: Exception) {
            false
        }
    }

    /** 请求激活设备管理员 */
    private fun requestActivation(context: Context) {
        try {
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(
                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                    ComponentName(context, SelfAppDeviceAdmin::class.java)
                )
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "设备管理员权限用于防止在自律模式下被强制停止，确保守护功能的正常运行。"
                )
            }
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            Log.e(TAG, "请求激活失败", e)
        }
    }
}
