---
version: alpha
name: self-app
description: An Android self-discipline app that locks selected apps. Supports two modes: (1) Manual — tap to start guarding for a countdown, (2) Scheduled — set time ranges (e.g. 22:00-07:00) to automatically lock apps every day. User picks a blocklist, and the blocked apps become impossible to open during guard. No accounts, no cloud, no store listing — a personal tool. Built with Kotlin + Compose + AccessibilityService, running entirely on-device.

project:
  language: Kotlin 2.0+
  minSdk: 26
  targetSdk: 35
  buildSystem: Gradle KTS + Version Catalog
  architecture: Single-module MVVM + Clean Architecture
  packageName: com.selfapp

guard_modes:
  manual:
    description: 手动开启，倒计时归零后自动结束
    user_input: 选择时长（15分钟 / 25分钟 / 45分钟 / 1小时 / 2小时 / 自定义）
    end_trigger: AlarmManager 准时触发
    ui: 首页大开关 + LockScreen 倒计时
  scheduled:
    description: 按时间段自动开关，如"每天 22:00 到次日 07:00 自动锁机"
    user_input: 设置开始时间 + 结束时间 + 生效星期
    start_trigger: AlarmManager 准时触发启动守护
    end_trigger: AlarmManager 准时触发结束守护
    ui: 首页时间表卡片 + LockScreen 显示"定时守护中"
    support_cross_midnight: true（如 22:00 → 07:00 跨天）
    max_schedules: 5 个时间段

permissions:
  usage_stats:
    name: PACKAGE_USAGE_STATS
    description: 检测当前前台运行的 App
    request: Settings.ACTION_USAGE_ACCESS_SETTINGS
    required: true
  overlay:
    name: SYSTEM_ALERT_WINDOW
    description: 锁屏页面覆盖在其他 App 之上
    request: Settings.ACTION_MANAGE_OVERLAY_PERMISSION
    required: true
  accessibility:
    name: BIND_ACCESSIBILITY_SERVICE
    description: 拦截 Home / Recent / Back 按键
    request: Settings.ACTION_ACCESSIBILITY_SETTINGS
    required: true
  foreground_service:
    name: FOREGROUND_SERVICE + FOREGROUND_SERVICE_SPECIAL_USE
    description: 前台服务保活，防止被系统杀死
    required: true
  notifications:
    name: POST_NOTIFICATIONS
    description: 显示"守护中"常驻通知
    request: requestPermissions (Android 13+)
    required: true
  boot_completed:
    name: RECEIVE_BOOT_COMPLETED
    description: 开机后自动恢复守护状态 + 重新注册所有 Schedule 的 AlarmManager
    required: true
  exact_alarm:
    name: SCHEDULE_EXACT_ALARM
    description: 手动守护结束 & 定时守护的启动/结束都需要精确闹钟
    request: Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
    required: true
  query_packages:
    name: QUERY_ALL_PACKAGES
    description: 列出用户安装的所有 App 供选择
    required: true

navigation:
  routes:
    home:
      path: /home
      description: 首页 — 手动守护开关 + 定时计划卡片 + 已选限制应用列表
    app_select:
      path: /app-select
      description: 应用选择页 — 从已安装列表中勾选要限制的 App
    schedule_edit:
      path: /schedule-edit?scheduleId={id}
      description: 添加/编辑定时计划 — 时间选择器 + 星期多选 + 生效开关
    lock:
      path: /lock
      description: 锁屏守护页 — 全屏倒计时(手动) 或 时间段提示(定时)
    stats:
      path: /stats
      description: 统计页 — 当日被阻止次数、守护时长、按时段拆分

data:
  entities:
    blocklist_entry:
      table: blocklist
      fields:
        - name: package_name
          type: String (PK)
          description: 被限制的应用包名
        - name: label
          type: String
          description: 应用显示名称
        - name: added_at
          type: Long
          description: 添加时间戳
    guard_schedule:
      table: guard_schedules
      fields:
        - name: id
          type: Long (PK, autoGenerate)
          description: 自增主键
        - name: label
          type: String
          description: 计划名称，如"睡眠锁机"、"午休守护"
        - name: start_hour
          type: Int (0~23)
          description: 开始时间 — 小时
        - name: start_minute
          type: Int (0~59)
          description: 开始时间 — 分钟
        - name: end_hour
          type: Int (0~23)
          description: 结束时间 — 小时
        - name: end_minute
          type: Int (0~59)
          description: 结束时间 — 分钟
        - name: days_of_week
          type: Int (bitmask: bit0=周日, bit1=周一, ..., bit6=周六)
          description: 生效星期
        - name: enabled
          type: Boolean
          description: 该计划是否启用
        - name: created_at
          type: Long
          description: 创建时间戳
    guard_record:
      table: guard_records
      fields:
        - name: id
          type: Long (PK, autoGenerate)
          description: 自增主键
        - name: start_at
          type: Long
          description: 守护开始时间戳
        - name: end_at
          type: Long
          description: 守护结束时间戳
        - name: duration_ms
          type: Long
          description: 实际守护时长
        - name: trigger_type
          type: String
          description: MANUAL / SCHEDULED
        - name: schedule_id
          type: Long? (nullable FK)
          description: 若是定时触发，关联 guard_schedules.id
        - name: block_count
          type: Int
          description: 本次守护中被拦截的总次数
        - name: blocked_apps
          type: String
          description: JSON 数组 — 被拦截的 app 记录 [{pkg, count}]
    block_event:
      table: block_events
      fields:
        - name: id
          type: Long (PK, autoGenerate)
          description: 自增主键
        - name: guard_record_id
          type: Long (FK)
          description: 关联的守护记录
        - name: package_name
          type: String
          description: 被拦截的应用包名
        - name: label
          type: String
          description: 应用名称
        - name: timestamp
          type: Long
          description: 拦截发生时间

  datastore_keys:
    guard_active: Boolean (是否处于守护中)
    guard_start_at: Long (本次守护开始时间戳)
    guard_end_at: Long (本次守护预计结束时间戳)
    guard_trigger_type: String (MANUAL / SCHEDULED)
    guard_schedule_id: Long? (若是定时触发，记录 schedule id)
    selected_blocklist: Set<String> (当前选中的限制应用包名集合)

services:
  guard_controller:
    class: GuardControllerService
    type: Foreground Service (specialUse)
    description: 守护模式的核心服务（手动 & 定时共用）
    lifecycle: |
      startForeground(id, notification) → 启动前台
      onStartCommand(action=START_MANUAL, durationMs) → 注册 end Alarm + 启动 LockActivity
      onStartCommand(action=START_SCHEDULED, scheduleId) → 注册 end Alarm + 启动 LockActivity
      onStartCommand(action=STOP) → 取消 Alarm + 关闭 LockActivity + stopSelf
      onDestroy → 清理资源、写入 guard_record
    notification:
      title_manual: "手动守护进行中"
      title_scheduled: "定时守护中 · {schedule_label}"
      body: "受保护的应用已锁定"
      channel: guard-channel (importance=HIGH)

  schedule_manager:
    class: ScheduleManager
    type: Utility class (injected via Hilt)
    description: 定时计划的注册/取消/恢复管理器
    methods:
      registerAll: "开机时调用，遍历所有 enabled=true 的 schedule，为每个 schedule 注册两个 AlarmManager（start + end）"
      register: "为单个 schedule 注册 start Alarm + end Alarm"
      cancel: "为单个 schedule 取消所有 Alarm"
      calculateNextTrigger: "计算下一个触发时间戳（处理跨天、星期过滤）"
    alarm_actions:
      - "com.selfapp.ACTION_SCHEDULE_START（extra: scheduleId）→ ScheduleStartReceiver"
      - "com.selfapp.ACTION_SCHEDULE_END（extra: scheduleId）→ ScheduleEndReceiver"

  key_interceptor:
    class: KeyInterceptorService
    type: AccessibilityService
    description: 拦截系统按键
    config_xml: res/xml/accessibility_service_config.xml
    behaviors:
      onKeyEvent: "KEYCODE_HOME / KEYCODE_APP_SWITCH / KEYCODE_BACK → return true（吃掉事件）"
      onAccessibilityEvent: "TYPE_WINDOW_STATE_CHANGED → 检测前台包名"
      onServiceConnected: "读取当前守护状态"

  foreground_watcher:
    class: ForegroundWatcher
    type: Coroutine-based polling
    description: 每 1 秒检测当前前台 App
    interval: 1000ms
    logic: |
      UsageStatsManager.queryUsageStats(INTERVAL_BEST, now-5000, now)
        → 取 lastTimeUsed 最大的包名
        → 若在 blocklist 中 → 发送 ACTION_BLOCK 广播
        → 若非自家包名 → 立即拉起 LockActivity

  session_receiver:
    class: SessionEndReceiver
    type: BroadcastReceiver
    description: 接收手动守护的 AlarmManager 触发 → 结束守护

  schedule_receivers:
    schedule_start_receiver:
      class: ScheduleStartReceiver
      description: 接收定时计划的启动 Alarm → 调 GuardControllerService.start(SCHEDULED)
    schedule_end_receiver:
      class: ScheduleEndReceiver
      description: 接收定时计划的结束 Alarm → 调 GuardControllerService.stop()

colors:
  primary: "#0066cc"
  primary-focus: "#0071e3"
  primary-on-dark: "#2997ff"
  ink: "#1d1d1f"
  body: "#1d1d1f"
  body-on-dark: "#ffffff"
  body-muted: "#cccccc"
  ink-muted-80: "#333333"
  ink-muted-48: "#7a7a7a"
  divider-soft: "#f0f0f0"
  hairline: "#e0e0e0"
  canvas: "#ffffff"
  canvas-parchment: "#f5f5f7"
  surface-pearl: "#fafafc"
  surface-tile-1: "#272729"
  surface-tile-2: "#2a2a2c"
  surface-tile-3: "#252527"
  surface-black: "#000000"
  surface-chip-translucent: "#d2d2d7"
  on-primary: "#ffffff"
  on-dark: "#ffffff"
  danger: "#ff3b30"
  danger-soft: "#ff6961"
  warning: "#ff9500"
  success: "#34c759"

typography:
  hero-display:
    fontFamily: "SF Pro Display, system-ui, -apple-system, sans-serif"
    fontSize: 56sp
    fontWeight: 600
    letterSpacing: -0.28sp
    usage: "锁屏倒计时大数字（Apple tight 标题感）"
  display_lg:
    fontFamily: "SF Pro Display, system-ui, -apple-system, sans-serif"
    fontSize: 40sp
    fontWeight: 600
    letterSpacing: 0
    usage: "统计页累计小时、大标题"
  display_md:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 34sp
    fontWeight: 600
    letterSpacing: -0.374sp
    usage: "页面主标题（SF Pro Text at display proportions）"
  headline:
    fontFamily: "SF Pro Display, system-ui, -apple-system, sans-serif"
    fontSize: 28sp
    fontWeight: 400
    letterSpacing: 0.196sp
    usage: "副标题、引导语"
  title:
    fontFamily: "SF Pro Display, system-ui, -apple-system, sans-serif"
    fontSize: 21sp
    fontWeight: 600
    letterSpacing: 0.231sp
    usage: "卡片标题、设置项标题、子标题标签"
  body:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 17sp
    fontWeight: 400
    lineHeight: 1.47
    letterSpacing: -0.374sp
    usage: "正文、说明文字（Apple 标准 17px body）"
  body_bold:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 17sp
    fontWeight: 600
    letterSpacing: -0.374sp
    usage: "强调正文"
  body_strong:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 17sp
    fontWeight: 600
    lineHeight: 1.24
    letterSpacing: -0.374sp
    usage: "行内强调"
  caption:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 14sp
    fontWeight: 400
    lineHeight: 1.43
    letterSpacing: -0.224sp
    usage: "辅助说明、应用包名"
  caption_strong:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 14sp
    fontWeight: 600
    lineHeight: 1.29
    letterSpacing: -0.224sp
    usage: "强调说明文字"
  button_large:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 18sp
    fontWeight: 300
    lineHeight: 1.0
    usage: "主要按钮文字（CTA）"
  button_utility:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 14sp
    fontWeight: 400
    lineHeight: 1.29
    usage: "次要按钮/导航按钮文字"
  label:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 12sp
    fontWeight: 500
    letterSpacing: 0.5
    usage: "标签、角标"
  fine_print:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 12sp
    fontWeight: 400
    usage: "法律声明、极小辅助文字"
  lead_airy:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 24sp
    fontWeight: 300
    lineHeight: 1.5
    usage: "轻量引导语（Apple 罕用 weight 300）"
  dense_link:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 17sp
    fontWeight: 400
    lineHeight: 2.41
    usage: "密集链接列表（footer/设置项列表）"
  micro_legal:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 10sp
    fontWeight: 400
    lineHeight: 1.3
    usage: "微型法律免责声明"
  nav_link:
    fontFamily: "SF Pro Text, system-ui, -apple-system, sans-serif"
    fontSize: 12sp
    fontWeight: 400
    usage: "导航菜单项"

rounded:
  none: 0dp
  xs: 5dp
  sm: 8dp
  md: 11dp
  lg: 18dp
  pill: 9999dp
  full: 9999dp

spacing:
  xxs: 4dp
  xs: 8dp
  sm: 12dp
  md: 17dp
  lg: 24dp
  xl: 32dp
  xxl: 48dp
  section: 80dp

components:
  guard_toggle:
    description: 首页核心开关（手动模式）
    visual: "大尺寸 Switch + 脉冲光圈动画"
    states:
      idle: "Switch=OFF, 底部展示已选应用列表"
      active: "Switch=ON, 光圈呼吸动画, 显示剩余时间"
      disabled: "Switch=OFF, 灰色, 提示'请先选择至少一个应用'"
      blocked_by_schedule: "Switch 被替换为'定时守护已生效'提示卡片"

  schedule_card:
    description: 定时计划卡片（首页展示）
    visual: |
      surface-card 背景, lg 圆角
      左侧: 大号时钟图标 + 时间段文字("22:00 - 07:00")
      右侧: Switch 开关（单独启停该计划）
      下方: "每天 工作日" 等星期标签(chip)
    states:
      enabled: "primary 色时钟图标 + 右侧 Switch=ON"
      disabled: "text-muted 色 + 右侧 Switch=OFF"
      active_now: "整张卡片 primary 描边 + '进行中' 角标"

  time_range_picker:
    description: 时间段选择器（schedule_edit 页面使用）
    visual: |
      两行 Material3 TimePicker 风格:
      ┌─────────────────────────┐
      │  开始时间               │
      │  [22] : [00]            │  ← 小时/分钟两列滚轮
      ├─────────────────────────┤
      │  结束时间               │
      │  [07] : [00]            │
      └─────────────────────────┘
      提示: "跨天守护 · 次日 07:00 解锁"

  weekday_chips:
    description: 星期多选组件
    visual: "水平排列 7 个 pill chip: 一 二 三 四 五 六 日"
    states:
      selected: "primary 填充 + text-on-primary"
      unselected: "透明底 + border 描边 + text-secondary"

  blocklist_card:
    description: 单个被限制应用的卡片
    visual: "App 图标 + 名称 + 删除按钮"
    states:
      normal: "surface-card 背景"
      guarded: "左下角显示小锁图标"

  app_select_item:
    description: 应用选择页的单个应用条目
    visual: "Checkbox + App 图标 + 应用名称 + 包名(caption)"
    states:
      unchecked: "border 描边"
      checked: "primary 填充 + 对勾"

  lock_overlay:
    description: 全屏守护覆盖层
    visual: |
      黑色全屏背景
      中央: 大号倒计时（display_lg, primary 色, 带发光）—— 手动模式
           或 "定时守护中" 大标题 —— 定时模式
      副标题: "受保护的应用已锁定"
      定时模式额外展示: "每天 22:00 - 07:00"
      底部: 被限制应用图标列表（不可点击）
    behaviors:
      onBackPressed: "空实现（不可返回）"
      onUserLeaveHint: "300ms 内重新拉起自己"
      onPause: "如果非 finishing，1 秒后重新置顶"

  stat_card:
    description: 统计卡片
    visual: "surface-card 背景, lg 圆角, 顶部标签 + 大数字"
    variants:
      total_guard_time: "累计守护时长 (display_md)"
      today_block_count: "今日拦截次数 (display_md)"
      streak_days: "连续守护天数 (display_md)"

  app_chip:
    description: 应用标签
    visual: "App 图标(20dp) + 名称(label), pill 形状, border 描边"
    usage: "首页已选应用列表、锁屏页已保护应用展示"
    states:
      normal: "透明底 + border"
      blocked: "danger-soft 底 + 危险图标"

  permission_item:
    description: 权限列表项
    visual: "图标 + 权限名称 + 状态标签(已授权/未授权)"
    states:
      granted: "success 色对勾"
      denied: "danger 色叉号, 整行可点击跳系统设置"

---

## Overview

SelfApp 是一个**个人使用的 Android 自律工具**。核心功能：**选好要限制的 App，设定好时间段，到点自动锁死这些 App，让你想玩也玩不了。**

支持两种守护模式：

| 模式 | 触发方式 | 结束方式 | 适用场景 |
|------|---------|---------|---------|
| **手动守护** | 点击开关，倒计时 N 分钟 | 倒计时归零 | 临时需要专注（"我要学习 2 小时"） |
| **定时守护** | 按设定时间自动触发 | 到设定结束时间 | 作息管理（"每晚 22 点自动锁微信抖音"） |

两种模式共享同一套锁屏机制（LockActivity + AccessibilityService + ForegroundWatcher），区别仅在于**启动信号来源不同**。

没有账号系统，没有云端同步，不需要上架应用商店。它就是一个装在手机里的"定时门禁"——到点自动锁，该玩玩的时候才放开。

### 核心交互流

```
             ┌──────────────┐
             │   用户设置    │
             │   一次性工作  │
             └──────┬───────┘
                    │
    ┌───────────────┼───────────────┐
    │               │               │
    ▼               ▼               ▼
授权 3 个权限    选限制 App     设定定时计划
                    │          ┌──────────────┐
                    │          │ "睡眠锁机"    │
                    │          │ 22:00→07:00  │
                    │          │ 每天          │
                    │          └──────┬───────┘
                    │               │
                    ▼               ▼
            ┌──────────────────────────────┐
            │         首页                  │
            │                              │
            │   [手动开关]   [定时计划卡片]   │
            │                              │
            └──────────────┬───────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
      [手动: 用户点开关]          [定时: 22:00 到]
              │                         │
              └──────────┬──────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  GuardController    │
              │  startForeground()  │
              └──────────┬──────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  全屏锁屏覆盖层      │
              │                     │
              │  倒计时 或 定时中    │
              │  "受保护App已锁定"   │
              │  [微信][抖音][B站]   │
              └─────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
       用户试图打开抖音        倒计时归零 / 定时到
              │                     │
              ▼                     ▼
       抖音弹出即被杀          锁屏消失，写 guard_record
       + 写 block_event        trigger_type = MANUAL/SCHEDULED
              │
              ▼
       自动跳回锁屏覆盖层
       (整个过程 < 500ms)
```

### 与市面上其他 App 的区别

| 特性 | SelfApp | 番茄ToDo | Forest | 不做手机控 |
|------|---------|----------|--------|-----------|
| 按时间段自动锁机 | **核心功能** | 无 | 无 | 有(弱) |
| 锁定特定 App | **有** | 白名单模式 | 无 | 有 |
| 需要账号 | **不需要** | 需要 | 需要 | 需要 |
| 绕过难度 | **高（无障碍拦截）** | 中 | 低 | 中 |
| 功能复杂度 | **简洁（5 个页面）** | 中等 | 中等 | 高 |
| APK 大小 | **< 8MB** | ~40MB | ~60MB | ~30MB |

### 设计原则

1. **不可绕过是第一要务**。手动守护开始、或定时计划到点后，唯一出口是等待到结束时间。任何允许用户"先关掉再玩"的设计都是失败的。
2. **设定一次，自动运转**。定时计划创建后无需再操心。每天到点自动锁、到点自动放，无需每天手动操作。
3. **手动 + 定时互不冲突**。如果手动守护正在进行时定时结束时间到了，定时结束信号优先。如果定时守护正在进行时用户想手动开始，提示"已在定时守护中"。
4. **不联网、不注册、不社交**。这是一个工具，不是一个平台。所有数据留在本地 Room 数据库。
5. **暗色主题默认**。守护场景意味着用户希望远离屏幕，亮色 UI 与此心理模型冲突。
6. **每一秒都有记录**。每次拦截、每次守护起止都写入数据库，并标记触发来源（手动/定时），用户回头看统计时有"确实有用"的反馈。

---

## Architecture

### 分层结构

```
app/src/main/java/com/selfapp/
├── SelfApp.kt                     # Application — Hilt 入口
├── MainActivity.kt                # 唯一 Activity（锁屏覆盖层除外）
│
├── core/
│   ├── di/                        # Hilt Module
│   ├── data/
│   │   ├── local/
│   │   │   ├── AppDatabase.kt     # Room 数据库
│   │   │   ├── dao/
│   │   │   │   ├── BlocklistDao.kt
│   │   │   │   ├── GuardScheduleDao.kt    # NEW
│   │   │   │   ├── GuardRecordDao.kt
│   │   │   │   └── BlockEventDao.kt
│   │   │   └── PreferencesDataStore.kt
│   │   ├── repository/
│   │   │   ├── BlocklistRepository.kt
│   │   │   ├── ScheduleRepository.kt       # NEW
│   │   │   ├── GuardRepository.kt
│   │   │   └── UsageStatsRepository.kt
│   │   └── model/                 # Room Entity 定义
│   ├── domain/
│   │   ├── model/                 # Domain 纯数据类
│   │   └── usecase/
│   │       ├── StartGuardUseCase.kt
│   │       ├── StopGuardUseCase.kt
│   │       ├── GetInstalledAppsUseCase.kt
│   │       ├── UpdateBlocklistUseCase.kt
│   │       ├── GetStatsUseCase.kt
│   │       ├── SaveScheduleUseCase.kt      # NEW
│   │       ├── DeleteScheduleUseCase.kt    # NEW
│   │       └── ToggleScheduleUseCase.kt    # NEW
│   ├── ui/
│   │   ├── theme/                 # Material3 主题 + 暗色默认
│   │   └── components/            # 通用 Composable (TimeRangePicker, WeekdayChips etc.)
│   └── util/                      # 扩展函数、时间计算工具
│
├── feature/
│   ├── home/
│   │   ├── HomeScreen.kt
│   │   └── HomeViewModel.kt
│   ├── appselect/
│   │   ├── AppSelectScreen.kt
│   │   └── AppSelectViewModel.kt
│   ├── schedule/                              # NEW
│   │   ├── ScheduleEditScreen.kt
│   │   └── ScheduleEditViewModel.kt
│   ├── lock/
│   │   ├── LockActivity.kt        # 独立 Activity (singleInstance)
│   │   └── LockScreen.kt
│   └── stats/
│       ├── StatsScreen.kt
│       └── StatsViewModel.kt
│
├── service/
│   ├── GuardControllerService.kt  # 前台服务
│   ├── ScheduleManager.kt         # NEW: 定时计划的 Alarm 注册/管理
│   ├── KeyInterceptorService.kt   # 无障碍服务
│   ├── ForegroundWatcher.kt       # 前台 App 轮询
│   ├── SessionEndReceiver.kt      # 手动守护结束广播
│   ├── ScheduleStartReceiver.kt   # NEW: 定时守护开始广播
│   └── ScheduleEndReceiver.kt     # NEW: 定时守护结束广播
│
└── navigation/
    └── AppNavGraph.kt             # Navigation Compose 路由
```

### 数据流

```
User Action / AlarmManager
    │
    ▼
ViewModel (StateFlow<UiState>)
    │
    ▼
UseCase (suspend fun / Flow)
    │
    ├── Repository (接口)
    │       │
    │       ├── Room DAO (持久化)
    │       └── DataStore (配置)
    │
    └── System Service
            ├── UsageStatsManager (前台检测)
            ├── AlarmManager (手动结束 + 定时启停)
            ├── ScheduleManager (定时 Alarm 注册/恢复)
            └── AccessibilityService (按键拦截)
```

### 依赖注入

单模块项目，Hilt 标准三件套：

| Module | 提供 |
|--------|------|
| `DatabaseModule` | Room DB + 四个 DAO |
| `RepositoryModule` | 四个 Repository 的接口绑定 |
| `ServiceModule` | GuardControllerService + ScheduleManager 需要的 Context |

所有 ViewModel 通过 `@HiltViewModel` + `@Inject constructor` 获取 UseCase。

---

## Core Flow: 两种守护模式的完整生命周期

### 定时守护 — 设定与管理

```
用户进入首页 → 点击"添加定时计划"卡片
  │
  ▼
ScheduleEditScreen (新建 / 编辑)
  │
  ├── ① 自定义计划名称: "睡眠锁机"
  ├── ② 时间选择:
  │     TimeRangePicker
  │     开始 22:00  →  结束   07:00
  │     (自动检测跨天，提示"次日 07:00")
  ├── ③ 星期选择:
  │     WeekdayChips
  │     [一] [二] [三] [四] [五] [六] [日]
  │     选中: primary 填充
  ├── ④ 计划开关: Switch 启用/停用
  │
  └── ⑤ 确认保存
        ├── GuardScheduleDao.insert / update
        ├── ScheduleManager.cancel(id) → 取消旧的 Alarm
        └── ScheduleManager.register(id) → 注册新的 start + end Alarm
```

### 定时守护 — 自动启动

```
ScheduleStartReceiver.onReceive(intent: scheduleId=3)
  │
  ├── ① 检查条件
  │     ├── schedule.enabled == true ?
  │     ├── 不是今天已经启动过了？（防止重复 Alarm）
  │     └── 当前是否已在守护中？
  │         └── 是 → 无操作（不重复启动）
  │
  ├── ② StartGuardUseCase.execute(triggerType=SCHEDULED, scheduleId=3)
  │     ├── DataStore: guard_active=true, trigger_type=SCHEDULED, schedule_id=3
  │     ├── GuardControllerService.startForeground(SCHEDULED, scheduleId)
  │     │     └── 通知标题: "定时守护中 · 睡眠锁机"
  │     ├── AlarmManager.setExact(END_AT, pendingIntent → SessionEndReceiver)
  │     │     └── 结束时间 = schedule.end_hour:end_minute 转换为时间戳
  │     └── 启动 LockActivity
  │
  └── ③ UI 反应
        LockScreen 展示: "定时守护中" + "每天 22:00 - 07:00"（无倒计时数字）
        首页: schedule_card 变成 active 状态（primary 描边 + "进行中"角标）
```

### 定时守护 — 自动结束

```
ScheduleEndReceiver.onReceive(intent: scheduleId=3)
  │
  └── StopGuardUseCase.execute(triggerType=SCHEDULED)
        ├── GuardControllerService.stopForeground()
        ├── AlarmManager.cancel()
        ├── DataStore: guard_active=false
        └── GuardRecordDao.insert(trigger_type=SCHEDULED, scheduleId=3)
              └── 发送广播关闭 LockActivity
```

### 手动守护 — 启动

```
HomeViewModel.toggleGuard(true)
  │
  ├── ① 检查是否已在定时守护中
  │     guard_active && trigger_type == SCHEDULED
  │     → 弹 Dialog: "定时守护'睡眠锁机'进行中，无法手动重复开启"
  │     → return
  │
  ├── ② 检查权限
  │     hasUsageStats() ∧ hasOverlay() ∧ isAccessibilityEnabled()
  │     任一缺失 → 弹 Dialog 引导授权
  │
  ├── ③ 检查 blocklist 非空
  │     blocklist.isEmpty() → 提示"请先选择要限制的应用"
  │
  ├── ④ StartGuardUseCase.execute(triggerType=MANUAL, durationMs=...)
  │     ├── DataStore: guard_active=true, trigger_type=MANUAL, start_at, end_at
  │     ├── GuardControllerService.startForeground(MANUAL, durationMs)
  │     ├── AlarmManager.setExact(END_AT, → SessionEndReceiver)
  │     └── 启动 LockActivity
  │
  └── ⑤ UI 反应
        HomeScreen: switch 置 ON, 脉冲动画开始, 显示倒计时
        LockScreen: 展示倒计时 "01:29:55"
```

### 手动守护 — 结束

```
触发方式:
  A. AlarmManager 准时触发
  B. 用户关机后开机 → BootReceiver 检测超过 end_at → 自动结束

SessionEndReceiver.onReceive()
  │
  └── StopGuardUseCase.execute(triggerType=MANUAL)
        同定时结束逻辑
```

### 开机恢复

```
BootReceiver.onReceive()
  │
  ├── ① 恢复进行中的守护
  │     DataStore.guard_active == true AND System.currentTimeMillis() < guard_end_at
  │     → GuardControllerService.startForeground() + 重设 AlarmManager
  │
  ├── ② 清理已过期的守护
  │     DataStore.guard_active == true AND System.currentTimeMillis() > guard_end_at
  │     → StopGuardUseCase.execute() (计入 guard_record)
  │
  └── ③ 恢复所有定时计划
        ScheduleManager.registerAll()
          → 遍历所有 enabled=true 的 schedule
          → 为每个 schedule 注册 start Alarm + end Alarm
          → calculateNextTrigger() 处理跨天 + 星期过滤
```

### 拦截前台 App

（手动 & 定时共用，逻辑不变）

```
ForegroundWatcher (每 1000ms 轮询)
  │
  ├── UsageStatsManager.queryUsageStats(INTERVAL_BEST, now-5s, now)
  ├── 取 lastTimeUsed 最大者 = foregroundPkg
  │
  ├── if foregroundPkg == 自家包名 → 跳过
  ├── if foregroundPkg in blocklist → 拦截
  │     ├── BlockEventDao.insert(BlockEvent)
  │     ├── finishAndRemoveTask() 当前前台 Activity (需要无障碍协助)
  │     └── startActivity(LockActivity)
  │
  └── if foregroundPkg == 系统桌面 → 拉起 LockActivity (用户试图按 Home)
```

### 屏蔽系统按键（AccessibilityService）

（手动 & 定时共用，逻辑不变）

```kotlin
// 按键拦截
override fun onKeyEvent(event: KeyEvent): Boolean {
    if (!isGuarding()) return super.onKeyEvent(event)

    return when (event.keyCode) {
        KeyEvent.KEYCODE_HOME,
        KeyEvent.KEYCODE_APP_SWITCH,
        KeyEvent.KEYCODE_BACK
            -> true  // 吃掉事件
        else -> super.onKeyEvent(event)
    }
}

// 窗口切换监控
override fun onAccessibilityEvent(event: AccessibilityEvent) {
    if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
    if (!isGuarding()) return

    val pkg = event.packageName?.toString() ?: return
    if (pkg in blocklist || pkg.startsWith("com.android.launcher")) {
        val intent = Intent(this, LockActivity::class.java)
            .addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_CLEAR_TOP)
        startActivity(intent)
    }
}
```

### LockActivity 的生命周期保护

（手动 & 定时共用，逻辑不变）

```kotlin
class LockActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(
            FLAG_KEEP_SCREEN_ON or
            FLAG_DISMISS_KEYGUARD or
            FLAG_SHOW_WHEN_LOCKED or
            FLAG_TURN_SCREEN_ON
        )
        setContent { LockScreen() }
    }

    override fun onBackPressed() { /* 吃掉返回键 */ }

    override fun onPause() {
        super.onPause()
        if (isFinishing) return
        if (!isGuarding()) { finish(); return }
        Handler(Looper.getMainLooper()).postDelayed({
            if (!isFinishing && isGuarding()) {
                startActivity(Intent(this, LockActivity::class.java)
                    .addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_REORDER_TO_FRONT))
            }
        }, 1000)
    }
}
```

### ScheduleManager 核心逻辑

```kotlin
class ScheduleManager @Inject constructor(
    @ApplicationContext private val ctx: Context,
    private val scheduleRepository: ScheduleRepository
) {
    // 开机 / App 启动时调用
    suspend fun registerAll() {
        val schedules = scheduleRepository.getAllEnabled()
        schedules.forEach { register(it) }
    }

    // 单个 schedule 注册（修改或新增后调用）
    fun register(schedule: GuardSchedule) {
        val startTime = calculateNextTrigger(
            schedule.startHour, schedule.startMinute, schedule.daysOfWeek
        )
        val endTime = calculateNextTrigger(
            schedule.endHour, schedule.endMinute, schedule.daysOfWeek
        )
        // 跨天处理：如果 endTime < startTime，则 endTime += 1 天
        // 注册两个精确闹钟
        setAlarm(ACTION_SCHEDULE_START, schedule.id, startTime)
        setAlarm(ACTION_SCHEDULE_END, schedule.id, endTime)
    }

    fun cancel(scheduleId: Long) {
        cancelAlarm(ACTION_SCHEDULE_START, scheduleId)
        cancelAlarm(ACTION_SCHEDULE_END, scheduleId)
    }

    // 计算下一个触发时间（考虑星期过滤和跨天）
    private fun calculateNextTrigger(
        hour: Int, minute: Int, daysOfWeek: Int
    ): Long {
        // 从当前时间往后找第一个匹配的星期 + 时间
        // 使用 java.time.LocalDateTime
        // 返回 epoch millis
    }
}
```

---

## ScheduleManager 详细设计

### 跨天逻辑

```
用户设定: 开始 22:00, 结束 07:00 (次日)
         today | tomorrow
start_at →  22:00  ← end_at (need +1 day)
────────────────────────────────────→ time

处理:
  calculateEndTime(start=22:00, end=07:00)
  if end_hour*60+end_minute <= start_hour*60+start_minute:
      endTime += 1 day (跨天)
```

### 重复 Alarm 注册策略

每次 schedule 修改 / App 启动时，执行：

```
cancel 旧的 Alarm → register 新的 Alarm → 持久化到 Room
```

`calculateNextTrigger` 只计算**下一次**触发时间，不批量注册未来的所有日子。每次 Alarm 触发后，在 Receiver 中立即调用 `register(self)` 注册下一次。

```
ScheduleStartReceiver.onReceive()
  ├── 启动守护
  └── ScheduleManager.register(schedule)  // 注册明天的 start alarm

ScheduleEndReceiver.onReceive()
  ├── 结束守护
  └── ScheduleManager.register(schedule)  // 注册明天的 end alarm
```

这样避免了 Android 对批量 Alarm 的限制，且天然支持夏令时/时区变化。

### 手动 vs 定时冲突处理

| 当前状态 | 用户操作 | 结果 |
|---------|---------|------|
| 空闲 | 手动开启 | 正常启动手动守护 |
| 空闲 | 定时时间到 | 正常启动定时守护 |
| 手动守护中 | 定时结束时间到 | **忽略**（不同 trigger） |
| 手动守护中 | 手动关闭 | 正常结束 |
| 定时守护中 | 用户点手动开关 | **弹 Dialog 提示**"已在定时守护中，请等待定时结束" |
| 定时守护中 | 定时结束时间到 | 正常结束 |
| 手动守护中 | 另一个定时开始时间到 | **自动转换**→结束手动、启动定时（定时优先） |

---

## Permissions

### 权限申请流程

```
首次启动 App
  │
  ▼
权限检查页（一次性引导）
  │
  ├── ① UsageStats 授权
  ├── ② 悬浮窗权限
  ├── ③ 无障碍服务
  └── ④ 精确闹钟 (Android 12+)

全部通过 → 进入首页
```

（流程与之前一致，新增精确闹钟权限申请）

---

## Pages & UI

### HomeScreen（首页）

```
┌──────────────────────────────────────┐
│                                      │
│         手动守护                      │
│                                      │
│      ┌──────────────────┐            │
│      │    [大号开关]      │            │
│      │  守护模式 · 已关闭  │            │
│      │  选 25 分钟  [▼]   │            │
│      └──────────────────┘            │
│                                      │
│    ════════════════════════════       │
│                                      │
│         定时计划        [+ 添加]      │
│                                      │
│   ┌──────────────────────────────┐   │
│   │ 🕐 睡眠锁机          [Switch] │   │
│   │    22:00 - 07:00             │   │
│   │    [日][一][二][三][四][五][六]│   │
│   └──────────────────────────────┘   │
│                                      │
│   ┌──────────────────────────────┐   │
│   │ 🕐 午休守护          [Switch] │   │
│   │    13:00 - 14:00             │   │
│   │    [一][二][三][四][五]       │   │
│   └──────────────────────────────┘   │
│                                      │
│    ════════════════════════════       │
│                                      │
│   已选限制应用 (5)       [编辑]       │
│   [微信] [抖音] [B站] [小红书][王者]   │
│                                      │
│   本次守护    已守护 3 次              │
│   00:00:00    累计 2h 15min           │
│                                      │
└──────────────────────────────────────┘
```

**首页布局逻辑**：
- 顶部：手动守护区域（大开关 + 时长选择器）
- 中部：定时计划列表（卡片 + 单独开关）
- 底部：已选限制应用列表 + 统计摘要

**当定时守护进行中时**：手动守护区域替换为提示卡片"定时守护'睡眠锁机'进行中 · 将在 07:00 解锁"，大开关变为不可操作的灰色。

**时长选择器**：下拉或底部弹窗，选项：15分钟 / 25分钟 / 45分钟 / 1小时 / 2小时 / 自定义。

### ScheduleEditScreen（添加/编辑定时计划）

```
┌──────────────────────────────────────┐
│  ← 返回        添加定时计划           │
│                                      │
│  名称                                │
│  ┌──────────────────────────────┐    │
│  │ 睡眠锁机                      │    │
│  └──────────────────────────────┘    │
│                                      │
│  时间段                              │
│  ┌──────────────────────────────┐    │
│  │  开始时间         结束时间     │    │
│  │  [22] : [00]    [07] : [00]  │    │
│  │        ↑ 滚轮选择  ↑         │    │
│  │                              │    │
│  │  ℹ️ 跨天守护 · 次日 07:00 解锁│    │
│  └──────────────────────────────┘    │
│                                      │
│  生效日期                            │
│  [一] [二] [三] [四] [五] [六] [日]  │
│   ↑ 选中=praimary 填充  未选中=透明   │
│                                      │
│  快速设置: [每天] [工作日] [周末]     │
│                                      │
│    ════════════════════════════       │
│                                      │
│  启用此计划                          │
│  ┌──────────────────────────────┐    │
│  │ 启用                    [Switch] │
│  └──────────────────────────────┘    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │         保存                  │    │
│  └──────────────────────────────┘    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │    删除此计划 (红色)          │    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

### AppSelectScreen（应用选择）

（与之前设计一致）

```
┌─────────────────────────────────┐
│  ← 返回         选择限制应用      │
│                                 │
│  🔍 搜索应用...                  │
│                                 │
│  ■ 已选 5 个                     │
│                                 │
│  ☑ [i] 微信    com.tencent.mm   │
│  ☑ [i] 抖音    com.ss.android..│
│  ☐ [i] 支付宝  com.eg.android..│
│  ☐ [i] 淘宝    com.taobao.tao..│
│                                 │
│  ┌─────────────────────────┐    │
│  │     确认选择 (5)         │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

### LockScreen（守护覆盖层）

**手动模式：**

```
┌─────────────────────────────────┐
│                                 │
│           ┌───────┐             │
│           │  🛡️   │             │
│           └───────┘             │
│                                 │
│          01 : 23 : 45           │   ← 倒计时, primary glow
│                                 │
│      受保护的应用已锁定           │
│                                 │
│   [微信] [抖音] [B站] [小红书]    │
│                                 │
│       距离解锁还有               │
│       1 小时 23 分               │
│                                 │
└─────────────────────────────────┘
```

**定时模式：**

```
┌─────────────────────────────────┐
│                                 │
│           ┌───────┐             │
│           │  🛡️   │             │
│           └───────┘             │
│                                 │
│         定时守护中               │   ← 无倒计时, headline
│                                 │
│      受保护的应用已锁定           │
│                                 │
│     睡眠锁机                    │
│     每天 22:00 - 07:00          │   ← 显示计划名称和时间段
│                                 │
│   [微信] [抖音] [B站] [小红书]    │
│                                 │
│       将在 07:00 自动解锁        │
│                                 │
└─────────────────────────────────┘
```

### StatsScreen（统计）

（与之前设计一致，新增按触发类型拆分）

```
┌─────────────────────────────────┐
│  统计                           │
│                                 │
│  ┌─────────┐ ┌─────────┐       │
│  │累计守护  │ │今日拦截  │       │
│  │ 12h 30m │ │  47 次  │       │
│  └─────────┘ └─────────┘       │
│  ┌─────────┐ ┌─────────┐       │
│  │定时守护  │ │手动守护  │  ← NEW│
│  │ 8h 10m  │ │ 4h 20m  │       │
│  └─────────┘ └─────────┘       │
│                                 │
│  最近拦截                       │
│  1. 微信  23次  ████████       │
│  2. 抖音  12次  ████           │
│                                 │
│  最近守护记录                    │
│  06-03  [定时] 2h30m  拦截8次   │
│  06-02  [手动] 1h45m  拦截5次   │
└─────────────────────────────────┘
```

---

## Data Layer

### Room 数据库

```kotlin
@Database(
    entities = [
        BlocklistEntry::class,
        GuardSchedule::class,   // NEW
        GuardRecord::class,
        BlockEvent::class
    ],
    version = 1,
    exportSchema = false
)
```

### GuardSchedule DAO 关键查询

```kotlin
@Dao
interface GuardScheduleDao {

    @Query("SELECT * FROM guard_schedules ORDER BY created_at ASC")
    fun observeAll(): Flow<List<GuardSchedule>>

    @Query("SELECT * FROM guard_schedules WHERE enabled = 1")
    suspend fun getAllEnabled(): List<GuardSchedule>

    @Query("SELECT * FROM guard_schedules WHERE id = :id")
    suspend fun getById(id: Long): GuardSchedule?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(schedule: GuardSchedule): Long

    @Query("DELETE FROM guard_schedules WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("UPDATE guard_schedules SET enabled = :enabled WHERE id = :id")
    suspend fun setEnabled(id: Long, enabled: Boolean)
}
```

### GuardRecord DAO 更新查询

```kotlin
// 按触发类型拆分统计
@Query("""
    SELECT COALESCE(SUM(duration_ms), 0) FROM guard_records
    WHERE trigger_type = :type
""")
fun observeTotalGuardMsByType(type: String): Flow<Long>
```

### 存储设施对比

| 数据 | 存储 | 原因 |
|------|------|------|
| Blocklist (选择了哪些 App) | Room + DataStore 双写 | Room 做结构化查询，DataStore 给 ForegroundWatcher 快速读取 |
| GuardSchedules (定时计划列表) | Room | 需要列表查询 + 单独更新 |
| guard_active / start_at / end_at | DataStore | 热路径数据，服务/Receiver 需要快速读，不需查询 |
| guard_records / block_events | Room | 需按时间/类型聚合查询 |

---

## Error Handling

### 错误分级

| 级别 | 场景 | 处理 |
|------|------|------|
| Fatal | 无障碍服务被用户手动关闭 | 立弹全屏提示 + 守护失效 + 5 分钟冷却 |
| Fatal | 定时守护触发时发现无障碍已关 | 系统通知"定时守护'睡眠锁机'启动失败：无障碍服务未开启" |
| Warning | AlarmManager 被厂商延迟 | 前台服务内用 Handler 做 fallback 计时；延迟 < 5 分钟不报警 |
| Warning | 定时计划触发但 app 未安装 | 跳过，通知用户"计划中的某个 app 已卸载" |
| Info | UsageStats 返回空列表 | 重试 3 次，间隔 500ms |
| Info | 一个 schedule 的 Alarm 注册失败 | 标记该 schedule 为 error，其他 schedule 不受影响 |
| Silent | 单个 block_event 写入失败 | 忽略，不影响主流程 |

### 定时计划的异常状态

| 异常 | 检测方式 | UI 表现 |
|------|---------|---------|
| Alarm 注册失败 | 应用内标记 | 卡片左下角橙色叹号，可点修复 |
| 关联的 App 被卸载 | 启动守护前校验 blocklist 包名是否存在 | 启动失败通知 + 提示更新 blocklist |
| 跨天边界 | 正常，设计已覆盖 | 无需处理 |

---

## Testing

### 必须覆盖的测试场景

```
□ LockActivity.onBackPressed 不会结束 Activity
□ LockActivity.onPause 在守护中时自动重新拉起
□ KeyInterceptorService 拦截 HOME / RECENT / BACK 三个键
□ ForegroundWatcher 正确检测黑名单 App 并触发跳回
□ 权限缺失时 StartGuardUseCase 返回 Failure
□ AlarmManager 到期后 SessionEndReceiver 正确清理状态
□ BootReceiver 在 guard_active=true 且未过期时恢复守护
□ BootReceiver 在 guard_active=true 且已过期时自动清理
□ BootReceiver 重新注册所有启用的 schedule Alarm
□ blocklist 为空时点击手动开关不生效
□ 倒计时精确度误差 < 2 秒
□ ScheduleManager.calculateNextTrigger 正确处理跨天 (22:00→07:00)
□ ScheduleManager.calculateNextTrigger 正确处理星期过滤
□ 定时守护进行中时手动开关被阻止
□ 手动守护中时另一个 schedule 的 end_time 不会误结束手动守护
□ ScheduleStartReceiver 在 schedule.enabled=false 时不启动
□ 保存 schedule 后立即注册了正确的 AlarmManager pendingIntent
□ 删除 schedule 后对应的 Alarm 被取消
```

---

## 开发路线

| Phase | 内容 | 文件产出 |
|-------|------|---------|
| 0 | 项目初始化 | build.gradle.kts, AndroidManifest.xml, SelfApp.kt |
| 1 | 数据层 | Room Entity + DAO + Database + DataStore (含 GuardSchedule) |
| 2 | 权限系统 | PermissionChecker + 权限引导 UI |
| 3 | 应用选择 | AppSelectScreen + GetInstalledAppsUseCase |
| 4 | 首页 (手动守护) | HomeScreen + 开关 + blocklist 展示 |
| 5 | 守护服务 | GuardControllerService + AlarmManager |
| 6 | 锁屏覆盖层 | LockActivity + LockScreen (手动 + 定时双 UI) |
| 7 | 无障碍服务 | KeyInterceptorService + accessibility_config.xml |
| 8 | 前台检测 | ForegroundWatcher |
| 9 | 定时计划 CRUD | ScheduleEditScreen + ScheduleManager + ScheduleReceivers |
| 10 | 定时计划自动启停 | ScheduleStartReceiver + ScheduleEndReceiver + 冲突处理 |
| 11 | 开机恢复 | BootReceiver + ScheduleManager.registerAll() |
| 12 | 统计页 | StatsScreen + 按触发类型拆分 |
| 13 | 厂商适配 | 电池白名单引导 + 自启动设置跳转 |
| 14 | 打磨 | 动画、暗色主题、性能优化 |

---

## 手动守护时长单次上限

为了避免误操作，手动守护的最长时长限制为 **6 小时**。如需更长时间段的守护，请使用**定时计划**功能（定时计划无时长上限，由时间段自然决定）。

---

## Build & Deploy

不涉及 CI/CD、不涉及应用商店。

```bash
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### 最小 APK

目标 < 8MB。不引入任何第三方分析/广告/支付 SDK，Compose 仅引入 Material3 + Navigation。

---

## Do's and Don'ts

### Do

- 无障碍服务的 `onKeyEvent` 必须返回 `true` 而非调 `super`——返回 `true` 才真正吃掉事件。
- 使用 `SystemClock.elapsedRealtime()` 计算经过时长，防止用户改系统时间欺骗倒计时。
- 定时计划的启动和结束分别使用**两个**独立的 AlarmManager PendingIntent（action + scheduleId 区分）。
- 每次 schedule 修改后执行 `cancel → register` 确保 Alarm 不会重复或遗漏。
- 开机时调用 `ScheduleManager.registerAll()` 恢复所有定时计划。
- `LockActivity` 的 `launchMode` 设为 `singleInstance` + `excludeFromRecents=true`。
- `GuardControllerService` 在 `onStartCommand` 返回 `START_STICKY`。
- 手动 vs 定时的冲突通过 `trigger_type` DataStore 字段判断，不靠 timestamps 推断。
- 所有字符串资源定义在 `strings.xml`。

### Don't

- 不要在锁屏页提供任何"提前结束"的入口。
- 不要在 `ForegroundWatcher` 里做网络请求。
- 不要用 `GlobalScope.launch`。
- 不要硬编码包名。
- 不要引入任何需要联网的三方库。
- 不要在 `LockActivity.onPause` 里做重操作。
- 不要跳过权限检查。
- 不要在一个 schedule 的 start_time 和 end_time 相同的边界情况下启动守护（end == start 视为 0 时长，直接跳过）。
- 不要让两个 schedule 同时触发时双开 LockActivity（用 `singleInstance` 天然防止）。

---

## Known Gaps & Risks

| 风险 | 等级 | 缓解措施 | 残余风险 |
|------|------|---------|---------|
| 用户手动关闭无障碍服务 | **高** | 守护中每 30s 检测；定时触发前检查 | 用户仍可无视 |
| 厂商杀后台 | **高** | 前台服务 + START_STICKY + 电池白名单引导 | 部分 ROM 连前台服务一起杀 |
| 用户调系统时间绕过定时 | **中** | `SystemClock.elapsedRealtime` 做倒计时基准；定时计划受真实时间影响但结合 boot 检测 | 用户在守护间隙改时间仍可绕过 |
| 用户卸载 App | 中 | 不防御 | 完全无防御 |
| 用户强制关机 | 中 | BootReceiver 开机恢复 | 关机期间不可控 |
| 紧急电话无法拨打 | 低 | 拨号 App 默认在白名单 | 三方 VoIP 可能被误拦 |
| 多个 schedule 时间重叠 | 低 | 守护中不再启动第二个；先开始的先结束 | 无 |
| AlarmManager 在省电模式下延迟 | 中 | 前台 Service 内用 Handler 做 fallback | 极端情况下可能延迟数分钟 |

---

## Appendix A: 紧急退出机制

**连续点击锁屏页右上角 7 次** → 弹出密码输入框 → 输入 `198814` → 强制结束当前守护（同时取消当天的所有 pending schedule）。

---

## Appendix B: schedule 数据示例

```json
{
  "id": 1,
  "label": "睡眠锁机",
  "start_hour": 22,
  "start_minute": 0,
  "end_hour": 7,
  "end_minute": 0,
  "days_of_week": 127,
  "enabled": true,
  "created_at": 1717372800000
}
```

`days_of_week = 127` 二进制 `1111111` → 全选（周日到周六）。
`days_of_week = 62` 二进制 `0111110` → 周一到周五（工作日）。
