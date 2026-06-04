package com.example.selfapp

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys

/**
 * 加密 SharedPreferences 管理器
 *
 * 用于保护敏感数据：
 * - guard_state: 守护状态（激活/停止、时间戳等）
 * - blocklist: 应用黑名单包名列表
 * - schedules: 定时计划配置
 *
 * 使用 AndroidX Security 库的 EncryptedSharedPreferences，
 * 数据使用 AES-256-GCM 加密存储，密钥存储在 Android KeyStore 中。
 */
object EncryptedPrefsManager {

    private const val PREFS_NAME_GUARD_STATE = "encrypted_guard_state"
    private const val PREFS_NAME_BLOCKLIST = "encrypted_blocklist"
    private const val PREFS_NAME_SCHEDULES = "encrypted_schedules"

    private var _guardStatePrefs: android.content.SharedPreferences? = null
    private var _blocklistPrefs: android.content.SharedPreferences? = null
    private var _schedulesPrefs: android.content.SharedPreferences? = null

    /**
     * 初始化加密 SharedPreferences（应在 Application.onCreate() 中调用）
     */
    fun init(context: Context) {
        try {
            val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)

            _guardStatePrefs = EncryptedSharedPreferences.create(
                PREFS_NAME_GUARD_STATE,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            _blocklistPrefs = EncryptedSharedPreferences.create(
                PREFS_NAME_BLOCKLIST,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            _schedulesPrefs = EncryptedSharedPreferences.create(
                PREFS_NAME_SCHEDULES,
                masterKeyAlias,
                context,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            android.util.Log.d("EncryptedPrefs", "✅ 加密 SharedPreferences 初始化成功")
        } catch (e: Exception) {
            android.util.Log.e("EncryptedPrefs", "❌ 初始化失败，回退到普通 SharedPreferences", e)
            // 回退到普通 SharedPreferences（某些设备可能不支持）
            _guardStatePrefs = context.getSharedPreferences(PREFS_NAME_GUARD_STATE, Context.MODE_PRIVATE)
            _blocklistPrefs = context.getSharedPreferences(PREFS_NAME_BLOCKLIST, Context.MODE_PRIVATE)
            _schedulesPrefs = context.getSharedPreferences(PREFS_NAME_SCHEDULES, Context.MODE_PRIVATE)
        }
    }

    /** 获取守护状态加密存储 */
    fun getGuardStatePrefs(context: Context): android.content.SharedPreferences {
        if (_guardStatePrefs == null) init(context)
        return _guardStatePrefs ?: context.getSharedPreferences(PREFS_NAME_GUARD_STATE, Context.MODE_PRIVATE)
    }

    /** 获取黑名单加密存储 */
    fun getBlocklistPrefs(context: Context): android.content.SharedPreferences {
        if (_blocklistPrefs == null) init(context)
        return _blocklistPrefs ?: context.getSharedPreferences(PREFS_NAME_BLOCKLIST, Context.MODE_PRIVATE)
    }

    /** 获取定时计划加密存储 */
    fun getSchedulesPrefs(context: Context): android.content.SharedPreferences {
        if (_schedulesPrefs == null) init(context)
        return _schedulesPrefs ?: context.getSharedPreferences(PREFS_NAME_SCHEDULES, Context.MODE_PRIVATE)
    }
}
