import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeChannel {
  static const _channel = MethodChannel('com.selfapp/native');

  // === 权限检查 ===
  static Future<bool> hasUsageStatsPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageStatsPermission') ?? false;
    } catch (e) {
      debugPrint('检查使用统计权限失败: $e');
      return false;
    }
  }

  static Future<void> requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
    } catch (e) {
      debugPrint('请求使用统计权限失败: $e');
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (e) {
      debugPrint('检查悬浮窗权限失败: $e');
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('请求悬浮窗权限失败: $e');
    }
  }

  static Future<bool> hasAccessibilityPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccessibilityPermission') ?? false;
    } catch (e) {
      debugPrint('检查无障碍权限失败: $e');
      return false;
    }
  }

  static Future<void> requestAccessibilityPermission() async {
    try {
      await _channel.invokeMethod('requestAccessibilityPermission');
    } catch (e) {
      debugPrint('请求无障碍权限失败: $e');
    }
  }

  // === 守护控制 ===
  static Future<void> startManualGuard(int durationMinutes) async {
    await _channel.invokeMethod('startManualGuard', {'durationMinutes': durationMinutes});
  }

  static Future<void> stopGuard() async {
    await _channel.invokeMethod('stopGuard');
  }

  // === 定时计划 ===
  static Future<void> registerSchedule(Map<String, dynamic> schedule) async {
    await _channel.invokeMethod('registerSchedule', schedule);
  }

  static Future<void> cancelSchedule(int scheduleId) async {
    await _channel.invokeMethod('cancelSchedule', {'scheduleId': scheduleId});
  }

  // === 应用列表 ===
  static Future<List<Map<String, String>>> getInstalledApps({String query = ''}) async {
    try {
      final result = await _channel.invokeMethod<Map>('getInstalledApps', {'query': query});
      if (result == null) return [];
      final apps = result['apps'] as List?;
      if (apps == null) return [];
      // MethodChannel 返回的是 Map<Object?, Object?>，需逐个转换
      return apps.map((e) {
        final m = e as Map;
        return {'packageName': m['packageName'].toString(), 'label': m['label'].toString()};
      }).toList();
    } catch (e) {
      debugPrint('获取应用列表失败: $e');
      return [];
    }
  }

  // === 黑名单同步 ===
  static Future<void> syncBlocklist(List<String> packages) async {
    try {
      await _channel.invokeMethod('syncBlocklist', {'packages': packages});
      debugPrint('同步黑名单: ${packages.length} 个应用');
    } catch (e) {
      debugPrint('同步黑名单失败: $e');
    }
  }

  // === 设备管理员权限 ===
  static Future<bool> hasDeviceAdminPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasDeviceAdmin') ?? false;
    } catch (e) {
      debugPrint('检查设备管理员权限失败: $e');
      return false;
    }
  }

  static Future<void> requestDeviceAdminPermission() async {
    try {
      await _channel.invokeMethod('requestDeviceAdmin');
    } catch (e) {
      debugPrint('请求设备管理员权限失败: $e');
    }
  }
}
