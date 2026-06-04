package com.example.selfapp

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import android.util.Log

/**
 * 惩戒覆盖层 Activity
 * 在黑名单应用上方全屏覆盖，用户必须完成困难退出才能解除。
 * 使用 LockTask 模式防止被切换走。
 */
class LockOverlayActivity : Activity() {

    companion object {
        private const val TAG = "LockOverlay"
        private const val TOTAL_STEPS = 5
        // 每步等待秒数 - 与 Flutter 端 ExitConfig 保持一致
        val STEP_WAIT_SECONDS = intArrayOf(15, 30, 45, 60, 10)
        // 每步标题 - 与 Flutter 端 ExitConfig.stepTitles 保持一致
        val STEP_TITLES = arrayOf(
            "你确定要放弃吗？",
            "冷静期 · 请再思考",
            "最后的反悔机会",
            "警告：即将解除所有保护",
            "守护即将结束"
        )
        // 每步励志文案
        val STEP_QUOTES = arrayOf(
            arrayOf(
                "现在的每一秒坚持，都在为未来的自由积累资本。",
                "你选择了开始，就一定有理由坚持下去。",
                "再给自己一点时间，你会发现其实没那么难。",
                "你的目标值得你此刻的坚持。"
            ),
            arrayOf(
                "每一次克制，都是对自我的超越。",
                "自律不是剥夺自由，而是选择更好的自由。",
                "想想当初为什么要开启这个守护？",
                "你比自己想象的更有毅力。"
            ),
            arrayOf(
                "坚持是世界上最难也最值得的事。",
                "不要让短暂的冲动毁掉长久的努力。",
                "此刻的不适，正是成长的声音。",
                "你离成功只差最后一次坚持。"
            ),
            arrayOf(
                "如果你确定要退出，请记住这不是失败。",
                "休息是为了走更远的路。",
                "感谢你今天的尝试，每一次努力都有意义。",
                "这不是结束，这是为下一次更好的准备。"
            ),
            arrayOf(
                "守护结束了，但自律的习惯可以继续。",
                "下次见面时，你会比现在更强大。",
                "你已经比大多数人更勇敢了。",
                "真正的自由来自自律。"
            )
        )

        fun start(context: Context, blockedPackage: String) {
            val intent = android.content.Intent(context, LockOverlayActivity::class.java).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                        android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        android.content.Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                putExtra("blocked_package", blockedPackage)
            }
            context.startActivity(intent)
        }
    }

    private var _currentStep = 0
    private var _countdownTimer: CountDownTimer? = null
    private var _isExiting = false
    private val _handler = Handler(Looper.getMainLooper())

    // UI components
    private lateinit var _iconView: TextView
    private lateinit var _titleView: TextView
    private lateinit var _quoteView: TextView
    private lateinit var _progressBar: ProgressBar
    private lateinit var _countdownView: TextView
    private lateinit var _actionButton: Button
    private lateinit var _cancelButton: TextView
    private lateinit var _stepIndicator: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 设置窗口属性：全屏覆盖 + 保持屏幕常亮 + 锁屏时也能显示
        window.apply {
            addFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            )
            // 半透明暗色背景
            setBackgroundDrawableResource(android.R.color.black)
        }

        val blockedPackage = intent?.getStringExtra("blocked_package") ?: ""
        buildUI(blockedPackage)

        // 尝试进入 LockTask 模式
        tryEnterLockTask()
        Log.d(TAG, "惩戒覆盖层已显示: $blockedPackage")
    }

    override fun onBackPressed() {
        // 拦截返回键
        Log.d(TAG, "🚫 拦截返回键")
    }

    override fun onPause() {
        super.onPause()
        // 如果用户尝试切走，延迟拉回
        if (!_isExiting) {
            _handler.postDelayed({
                if (!isFinishing && !_isExiting) {
                    Log.d(TAG, "⚠️ 检测到切走，拉回覆盖层")
                    // 重置退出步骤作为惩罚
                    resetSteps()
                }
            }, 300)
        }
    }

    override fun onResume() {
        super.onResume()
        if (!_isExiting) {
            tryEnterLockTask()
        }
    }

    private fun buildUI(blockedPackage: String) {
        val scrollView = ScrollView(this)
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 80, 48, 80)
            minimumHeight = resources.displayMetrics.heightPixels
        }

        // 标题：被拦截的应用
        val appName = getAppName(blockedPackage)
        val warningLabel = TextView(this).apply {
            text = "⚠️ $appName 已被限制"
            textSize = 13f
            setTextColor(Color.parseColor("#FF6B6B"))
            gravity = Gravity.CENTER
        }
        rootLayout.addView(warningLabel)

        // Space
        val spacer1 = Space(this)
        spacer1.minimumHeight = 40
        rootLayout.addView(spacer1)

        // 图标
        _iconView = TextView(this).apply {
            text = "🛡️"
            textSize = 48f
            gravity = Gravity.CENTER
        }
        rootLayout.addView(_iconView)

        val spacer2 = Space(this)
        spacer2.minimumHeight = 24
        rootLayout.addView(spacer2)

        // 进度条
        _progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = TOTAL_STEPS * 100
            progress = 0
            progressTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#FF6B6B"))
        }
        val pbParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 6
        )
        pbParams.setMargins(0, 0, 0, 24)
        rootLayout.addView(_progressBar, pbParams)

        // 步骤指示器
        _stepIndicator = TextView(this).apply {
            text = "步骤 0 / $TOTAL_STEPS"
            textSize = 12f
            setTextColor(Color.parseColor("#888888"))
            gravity = Gravity.CENTER
        }
        rootLayout.addView(_stepIndicator)

        val spacer3 = Space(this)
        spacer3.minimumHeight = 16
        rootLayout.addView(spacer3)

        // 标题
        _titleView = TextView(this).apply {
            text = "你打开了受限应用"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        rootLayout.addView(_titleView)

        val spacer4 = Space(this)
        spacer4.minimumHeight = 20
        rootLayout.addView(spacer4)

        // 励志文案
        _quoteView = TextView(this).apply {
            text = "完成以下步骤才能退出惩罚模式"
            textSize = 15f
            setTextColor(Color.parseColor("#BBBBBB"))
            gravity = Gravity.CENTER
            setLineSpacing(6f, 1.2f)
        }
        rootLayout.addView(_quoteView)

        val spacer5 = Space(this)
        spacer5.minimumHeight = 32
        rootLayout.addView(spacer5)

        // 倒计时
        _countdownView = TextView(this).apply {
            text = ""
            textSize = 36f
            setTextColor(Color.parseColor("#FF6B6B"))
            gravity = Gravity.CENTER
            setTypeface(null, android.graphics.Typeface.BOLD)
        }
        rootLayout.addView(_countdownView)

        val spacer6 = Space(this)
        spacer6.minimumHeight = 24
        rootLayout.addView(spacer6)

        // 操作按钮
        _actionButton = Button(this).apply {
            text = "开始退出流程"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#FF4444"))
            setOnClickListener { onActionClick() }
            minHeight = 120
            textSize = 16f
        }
        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        )
        btnParams.setMargins(0, 0, 0, 16)
        rootLayout.addView(_actionButton, btnParams)

        // 返回守护
        _cancelButton = TextView(this).apply {
            text = "我知道了，返回守护"
            textSize = 14f
            setTextColor(Color.parseColor("#666666"))
            gravity = Gravity.CENTER
            setOnClickListener {
                _isExiting = true
                finishOverlay()
            }
        }
        rootLayout.addView(_cancelButton)

        scrollView.addView(rootLayout)
        setContentView(scrollView)
    }

    private fun onActionClick() {
        if (_currentStep == 0) {
            // 开始退出流程
            startStep(1)
        } else if (_countdownTimer == null) {
            // 倒计时结束，进入下一步
            if (_currentStep >= TOTAL_STEPS) {
                completeExit()
            } else {
                startStep(_currentStep + 1)
            }
        }
        // 如果倒计时进行中，忽略点击
    }

    private fun startStep(step: Int) {
        _currentStep = step
        _countdownTimer?.cancel()

        val waitSeconds = STEP_WAIT_SECONDS[step - 1]
        val title = STEP_TITLES[step - 1]
        val quotes = STEP_QUOTES[step - 1]
        val quote = quotes[(Math.random() * quotes.size).toInt()]

        // 更新图标
        val icons = arrayOf("💪", "🧠", "⚡", "🔥", "🏆")
        _iconView.text = icons[step - 1]

        // 更新UI
        _titleView.text = title
        _quoteView.text = quote
        _stepIndicator.text = "步骤 $step / $TOTAL_STEPS"
        _progressBar.progress = step * 100

        // 禁用按钮，开始倒计时
        _actionButton.isEnabled = false
        _actionButton.text = "请等待 ${waitSeconds}s..."
        _actionButton.setBackgroundColor(Color.parseColor("#444444"))

        _countdownTimer = object : CountDownTimer(waitSeconds * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                val secs = millisUntilFinished / 1000
                _countdownView.text = "${secs}s"
                _actionButton.text = "请等待 ${secs}s..."
            }

            override fun onFinish() {
                _countdownView.text = ""
                _countdownTimer = null

                if (step >= TOTAL_STEPS) {
                    _actionButton.text = "✅ 确认退出"
                    _actionButton.setBackgroundColor(Color.parseColor("#34C759"))
                } else {
                    _actionButton.text = "继续下一步 →"
                    _actionButton.setBackgroundColor(Color.parseColor("#FF9500"))
                }
                _actionButton.isEnabled = true
            }
        }.start()
    }

    private fun completeExit() {
        _isExiting = true
        _countdownTimer?.cancel()

        // 退出 LockTask
        try {
            stopLockTask()
        } catch (_: Exception) {}

        // 显示完成提示
        _iconView.text = "✅"
        _titleView.text = "惩罚完成"
        _quoteView.text = "记住这次教训，下次打开受限应用前请三思。"
        _countdownView.text = ""
        _actionButton.visibility = View.GONE
        _cancelButton.text = "返回 (3s后自动关闭)"

        // 3秒后自动关闭
        _handler.postDelayed({
            finishOverlay()
        }, 3000)

        Log.d(TAG, "惩戒完成，覆盖层即将关闭")
    }

    private fun resetSteps() {
        _countdownTimer?.cancel()
        _countdownTimer = null
        _currentStep = 0
        _iconView.text = "🛡️"
        _titleView.text = "你打开了受限应用"
        _quoteView.text = "完成以下步骤才能退出惩罚模式\n\n⚠️ 步骤已重置"
        _countdownView.text = ""
        _stepIndicator.text = "步骤 0 / $TOTAL_STEPS"
        _progressBar.progress = 0
        _actionButton.apply {
            text = "开始退出流程"
            setBackgroundColor(Color.parseColor("#FF4444"))
            isEnabled = true
        }
    }

    private fun tryEnterLockTask() {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            val admin = ComponentName(this, SelfAppDeviceAdmin::class.java)
            if (dpm?.isAdminActive(admin) == true) {
                if (!dpm.isLockTaskPermitted(packageName)) {
                    dpm.setLockTaskPackages(admin, arrayOf(packageName))
                }
                startLockTask()
                Log.d(TAG, "🔒 LockTask 已激活")
            } else {
                // 无设备管理员时直接尝试
                try { startLockTask() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            Log.e(TAG, "LockTask失败: ${e.message}")
        }
    }

    private fun finishOverlay() {
        try { stopLockTask() } catch (_: Exception) {}
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        _countdownTimer?.cancel()
        _isExiting = true
        try { stopLockTask() } catch (_: Exception) {}
        Log.d(TAG, "覆盖层已销毁")
    }

    private fun getAppName(packageName: String): String {
        return try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(packageName, 0)
            ).toString()
        } catch (_: Exception) {
            packageName.substringAfterLast('.')
        }
    }
}
