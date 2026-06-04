import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

const _keySchedules = 'guard_schedules';
const _keyBlocklist = 'blocklist_entries';
const _keyGuardActive = 'guard_active';
const _keyGuardStartAt = 'guard_start_at';
const _keyGuardEndAt = 'guard_end_at';
const _keyGuardTriggerType = 'guard_trigger_type';
const _keyGuardScheduleId = 'guard_schedule_id';
const _keySelectedBlocklist = 'selected_blocklist';
// === 统计数据相关 ===
const _keyStatsTotalDurationMs = 'stats_total_duration_ms';
const _keyStatsTotalSessions = 'stats_total_sessions';
const _keyStatsTodayDurationMs = 'stats_today_duration_ms';
const _keyStatsTodaySessions = 'stats_today_sessions';
const _keyStatsTodayBlocks = 'stats_today_blocks';
const _keyStatsLastDate = 'stats_last_date';

class StorageService {
  static StorageService? _instance;
  static SharedPreferences? _prefs;

  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  StorageService._();

  SharedPreferences get prefs => _prefs!;

  // === Schedules ===
  List<GuardSchedule> getSchedules() {
    final raw = prefs.getString(_keySchedules);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => GuardSchedule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveSchedules(List<GuardSchedule> schedules) async {
    await prefs.setString(_keySchedules, jsonEncode(schedules.map((e) => e.toJson()).toList()));
  }

  // === Blocklist (DB entries) ===
  List<BlocklistEntry> getBlocklistEntries() {
    final raw = prefs.getString(_keyBlocklist);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => BlocklistEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveBlocklistEntries(List<BlocklistEntry> entries) async {
    await prefs.setString(_keyBlocklist, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  // === Selected blocklist (runtime set of package names) ===
  Set<String> getSelectedBlocklist() {
    final raw = prefs.getStringList(_keySelectedBlocklist);
    return raw?.toSet() ?? <String>{};
  }

  Future<void> setSelectedBlocklist(Set<String> packages) async {
    await prefs.setStringList(_keySelectedBlocklist, packages.toList());
  }

  // === Guard State ===
  // 注意：startAt/endAt 为毫秒级时间戳 (millisecondsSinceEpoch)
  // 与 Kotlin 端 putLong() 对应，Dart 在 Android 平台上 int 为 64 位，可安全存储
  GuardState getGuardState() {
    return GuardState(
      active: prefs.getBool(_keyGuardActive) ?? false,
      startAt: prefs.getInt(_keyGuardStartAt),
      endAt: prefs.getInt(_keyGuardEndAt),
      triggerType: prefs.getString(_keyGuardTriggerType),
      scheduleId: prefs.getInt(_keyGuardScheduleId),
    );
  }

  Future<void> setGuardSession({
    required int startAt,
    required int endAt,
    required String triggerType,
    int? scheduleId,
  }) async {
    await prefs.setBool(_keyGuardActive, true);
    await prefs.setInt(_keyGuardStartAt, startAt);
    await prefs.setInt(_keyGuardEndAt, endAt);
    await prefs.setString(_keyGuardTriggerType, triggerType);
    if (scheduleId != null) await prefs.setInt(_keyGuardScheduleId, scheduleId);
  }

  Future<void> clearGuardSession() async {
    await prefs.setBool(_keyGuardActive, false);
    await prefs.remove(_keyGuardStartAt);
    await prefs.remove(_keyGuardEndAt);
    await prefs.remove(_keyGuardTriggerType);
    await prefs.remove(_keyGuardScheduleId);
  }

  // === 统计数据 ===

  /// 获取统计数据
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastDateStr = prefs.getString(_keyStatsLastDate) ?? '';

    // 如果日期变了，重置今日数据
    if (lastDateStr != todayStr) {
      return {
        'totalDurationMs': prefs.getInt(_keyStatsTotalDurationMs) ?? 0,
        'totalSessions': prefs.getInt(_keyStatsTotalSessions) ?? 0,
        'todayDurationMs': 0,
        'todaySessions': 0,
        'todayBlocks': 0,
      };
    }

    return {
      'totalDurationMs': prefs.getInt(_keyStatsTotalDurationMs) ?? 0,
      'totalSessions': prefs.getInt(_keyStatsTotalSessions) ?? 0,
      'todayDurationMs': prefs.getInt(_keyStatsTodayDurationMs) ?? 0,
      'todaySessions': prefs.getInt(_keyStatsTodaySessions) ?? 0,
      'todayBlocks': prefs.getInt(_keyStatsTodayBlocks) ?? 0,
    };
  }

  /// 记录一次守护会话结束
  Future<void> recordGuardSession({
    required int durationMs,
    required int blockCount,
  }) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastDateStr = prefs.getString(_keyStatsLastDate) ?? '';

    // 如果是新的一天，先重置今日数据
    if (lastDateStr != todayStr && lastDateStr.isNotEmpty) {
      await prefs.setInt(_keyStatsTodayDurationMs, 0);
      await prefs.setInt(_keyStatsTodaySessions, 0);
      await prefs.setInt(_keyStatsTodayBlocks, 0);
    }

    // 更新累计数据
    final totalDuration = (prefs.getInt(_keyStatsTotalDurationMs) ?? 0) + durationMs;
    final totalSessions = (prefs.getInt(_keyStatsTotalSessions) ?? 0) + 1;
    final todayDuration = (prefs.getInt(_keyStatsTodayDurationMs) ?? 0) + durationMs;
    final todaySessions = (prefs.getInt(_keyStatsTodaySessions) ?? 0) + 1;
    final todayBlocks = (prefs.getInt(_keyStatsTodayBlocks) ?? 0) + blockCount;

    await prefs.setInt(_keyStatsTotalDurationMs, totalDuration);
    await prefs.setInt(_keyStatsTotalSessions, totalSessions);
    await prefs.setInt(_keyStatsTodayDurationMs, todayDuration);
    await prefs.setInt(_keyStatsTodaySessions, todaySessions);
    await prefs.setInt(_keyStatsTodayBlocks, todayBlocks);
    await prefs.setString(_keyStatsLastDate, todayStr);
  }
}
