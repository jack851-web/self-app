import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/storage_service.dart';
import '../models/models.dart';
import '../services/native_channel.dart';

// === Storage Provider ===
final storageProvider = FutureProvider<StorageService>((ref) async {
  return await StorageService.getInstance();
});

// === Schedules Provider ===
final schedulesProvider = StateNotifierProvider<ScheduleNotifier, List<GuardSchedule>>((ref) {
  return ScheduleNotifier();
});

class ScheduleNotifier extends StateNotifier<List<GuardSchedule>> {
  ScheduleNotifier() : super([]);

  StorageService? _storage;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init(StorageService storage) async {
    _storage = storage;
    _initialized = true;
    state = storage.getSchedules();
    // 启动时重新注册所有已启用的定时计划到原生闹钟
    for (final s in state) {
      if (s.enabled) {
        try {
          await NativeChannel.registerSchedule(s.toJson());
        } catch (e) {
          debugPrint('注册定时计划失败 [${s.id}]: $e');
        }
      }
    }
  }

  void _checkInit() {
    if (!_initialized || _storage == null) {
      throw StateError('ScheduleNotifier 未初始化，请先调用 init()');
    }
  }

  Future<void> add(GuardSchedule schedule) async {
    _checkInit();
    final newSchedule = schedule.copyWith(id: DateTime.now().millisecondsSinceEpoch);
    state = [...state, newSchedule];
    await _storage!.saveSchedules(state);
    if (newSchedule.enabled) {
      try { 
        await NativeChannel.registerSchedule(newSchedule.toJson()); 
      } catch (e) { 
        debugPrint('注册新计划失败: $e'); 
      }
    }
  }

  Future<void> update(GuardSchedule schedule) async {
    _checkInit();
    state = state.map((s) => s.id == schedule.id ? schedule : s).toList();
    await _storage!.saveSchedules(state);
    try { 
      await NativeChannel.registerSchedule(schedule.toJson()); 
    } catch (e) { 
      debugPrint('更新计划失败: $e'); 
    }
  }

  Future<void> remove(int id) async {
    _checkInit();
    state = state.where((s) => s.id != id).toList();
    await _storage!.saveSchedules(state);
    try { 
      await NativeChannel.cancelSchedule(id); 
    } catch (e) { 
      debugPrint('取消计划失败: $e'); 
    }
  }

  Future<void> toggleEnabled(int id, bool enabled) async {
    _checkInit();
    state = state.map((s) => s.id == id ? s.copyWith(enabled: enabled) : s).toList();
    await _storage!.saveSchedules(state);
    final target = state.where((s) => s.id == id).firstOrNull;
    if (target != null) {
      try { 
        await NativeChannel.registerSchedule(target.toJson()); 
      } catch (e) { 
        debugPrint('切换计划状态失败: $e'); 
      }
    }
  }
}

// === Blocklist Provider ===
final blocklistEntriesProvider = StateNotifierProvider<BlocklistEntryNotifier, List<BlocklistEntry>>((ref) {
  return BlocklistEntryNotifier();
});

class BlocklistEntryNotifier extends StateNotifier<List<BlocklistEntry>> {
  BlocklistEntryNotifier() : super([]);

  StorageService? _storage;
  bool _initialized = false;

  Future<void> init(StorageService storage) async {
    _storage = storage;
    _initialized = true;
    state = storage.getBlocklistEntries();
  }

  void _checkInit() {
    if (!_initialized || _storage == null) {
      throw StateError('BlocklistEntryNotifier 未初始化，请先调用 init()');
    }
  }

  Future<void> add(BlocklistEntry entry) async {
    _checkInit();
    if (state.any((e) => e.packageName == entry.packageName)) return;
    state = [...state, entry];
    await _storage!.saveBlocklistEntries(state);
  }

  Future<void> remove(String packageName) async {
    _checkInit();
    state = state.where((e) => e.packageName != packageName).toList();
    await _storage!.saveBlocklistEntries(state);
  }
}

// === Selected Blocklist (runtime set) ===
final selectedBlocklistProvider = StateNotifierProvider<SelectedBlocklistNotifier, Set<String>>((ref) {
  return SelectedBlocklistNotifier();
});

class SelectedBlocklistNotifier extends StateNotifier<Set<String>> {
  SelectedBlocklistNotifier() : super(<String>{});

  StorageService? _storage;
  bool _initialized = false;

  Future<void> init(StorageService storage) async {
    _storage = storage;
    _initialized = true;
    state = storage.getSelectedBlocklist();
  }

  void _checkInit() {
    if (!_initialized || _storage == null) {
      throw StateError('SelectedBlocklistNotifier 未初始化，请先调用 init()');
    }
  }

  Future<void> add(String packageName) async {
    _checkInit();
    state = {...state, packageName};
    await _storage!.setSelectedBlocklist(state);
  }

  Future<void> remove(String packageName) async {
    _checkInit();
    state = state.difference({packageName});
    await _storage!.setSelectedBlocklist(state);
  }

  Future<void> setAll(Set<String> packages) async {
    _checkInit();
    state = packages;
    await _storage!.setSelectedBlocklist(packages);
  }
}

// === Guard State Provider ===
final guardStateProvider = StateNotifierProvider<GuardStateNotifier, GuardState>((ref) {
  return GuardStateNotifier();
});

class GuardStateNotifier extends StateNotifier<GuardState> {
  GuardStateNotifier() : super(const GuardState());

  StorageService? _storage;
  bool _initialized = false;

  Future<void> init(StorageService storage) async {
    _storage = storage;
    _initialized = true;
    state = storage.getGuardState();
  }

  void _checkInit() {
    if (!_initialized || _storage == null) {
      throw StateError('GuardStateNotifier 未初始化，请先调用 init()');
    }
  }

  Future<void> startManual(int durationMinutes, {List<String>? blocklist}) async {
    _checkInit();
    final now = DateTime.now().millisecondsSinceEpoch;
    final endAt = now + durationMinutes * 60 * 1000;
    await _storage!.setGuardSession(startAt: now, endAt: endAt, triggerType: 'MANUAL');
    state = GuardState(active: true, startAt: now, endAt: endAt, triggerType: 'MANUAL');
    
    // 同步黑名单到原生端（用于无障碍服务拦截）
    if (blocklist != null && blocklist.isNotEmpty) {
      try {
        await NativeChannel.syncBlocklist(blocklist);
        debugPrint('已同步 ${blocklist.length} 个应用到原生黑名单');
      } catch (e) {
        debugPrint('同步黑名单失败: $e');
      }
    }

    try { 
      await NativeChannel.startManualGuard(durationMinutes); 
    } catch (e) { 
      debugPrint('启动手动守护失败: $e'); 
    }
  }

  Future<void> startScheduled(int scheduleId) async {
    _checkInit();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _storage!.setGuardSession(startAt: now, endAt: 0, triggerType: 'SCHEDULED', scheduleId: scheduleId);
    state = GuardState(active: true, startAt: now, endAt: null, triggerType: 'SCHEDULED', scheduleId: scheduleId);
  }

  Future<void> stop() async {
    _checkInit();
    
    // 记录统计数据
    if (state.active && state.startAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final durationMs = now - state.startAt!;
      try {
        await _storage!.recordGuardSession(
          durationMs: durationMs,
          blockCount: 0, // TODO: 实现拦截计数
        );
      } catch (e) {
        debugPrint('记录统计数据失败: $e');
      }
    }
    
    await _storage!.clearGuardSession();
    state = const GuardState();
    try { await NativeChannel.stopGuard(); } catch (e) { debugPrint('停止守护失败: $e'); }
  }
}
