import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../config/app_config.dart';
import '../data/data4library_api_client.dart';
import '../models/loan_alert.dart';
import '../models/models.dart';

const loanAlertTaskName = 'k_library_loan_alert_check';
const loanAlertUniqueName = 'k_library_daily_loan_alert_check';
const maxLoanAlerts = 10;
const alertCheckCooldown = Duration(hours: 20);
final FlutterLocalNotificationsPlugin loanAlertNotifications =
    FlutterLocalNotificationsPlugin();

class LoanAlertService {
  LoanAlertService({Data4LibraryApiClient? api})
    : _api = api ?? Data4LibraryApiClient();
  final Data4LibraryApiClient _api;
  static const _key = 'loan_alert_items';

  Future<void> initialize() async {
    await loanAlertNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await Workmanager().initialize(loanAlertDispatcher);
    await Workmanager().registerPeriodicTask(
      loanAlertUniqueName,
      loanAlertTaskName,
      frequency: const Duration(hours: 24),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<List<LoanAlertItem>> list() async =>
      ((await SharedPreferences.getInstance()).getStringList(_key) ?? const [])
          .map(
            (e) => LoanAlertItem.fromJson(
              Map<String, dynamic>.from(jsonDecode(e) as Map),
            ),
          )
          .toList();

  Future<String?> add({
    required String title,
    required String isbn,
    required String libraryName,
    required String libraryCode,
    String homepage = '',
    String coverUrl = '',
  }) async {
    final items = await list();
    final id = '$isbn::$libraryCode';
    if (items.any((e) => e.id == id && e.active && !e.completed)) {
      return '이미 등록된 알림입니다.';
    }
    if (items.where((e) => e.active && !e.completed).length >= maxLoanAlerts) {
      return '대출 알림은 최대 10개까지 등록할 수 있습니다.';
    }
    final next = [
      LoanAlertItem(
        id: id,
        title: title,
        isbn: isbn,
        libraryName: libraryName,
        libraryCode: libraryCode,
        homepage: homepage,
        coverUrl: coverUrl,
        createdAt: DateTime.now(),
      ),
      ...items,
    ];
    await _save(next);
    await requestNotificationPermission();
    return null;
  }

  Future<void> remove(String id) async =>
      _save((await list()).where((e) => e.id != id).toList());
  Future<void> restart(String id) async => _save(
    (await list())
        .map(
          (e) => e.id == id
              ? e.copyWith(active: true, completed: false, lastStatus: '감시 중')
              : e,
        )
        .toList(),
  );

  Future<LoanAlertItem> checkNow(
    LoanAlertItem item, {
    bool notify = true,
  }) async {
    try {
      final status = await _api.bookExist(
        isbn: item.isbn,
        libCode: item.libraryCode,
      );
      final checked = DateTime.now();
      if (status == LoanStatus.available) {
        final next = item.copyWith(
          lastStatus: '대출 가능 확인',
          lastCheckedAt: checked,
          active: false,
          completed: true,
          failureCount: 0,
        );
        if (notify) {
          await _notify(next);
        }
        await _replace(next);
        return next;
      }
      final next = item.copyWith(
        lastStatus: status.label,
        lastCheckedAt: checked,
        failureCount: 0,
      );
      await _replace(next);
      return next;
    } catch (_) {
      final next = item.copyWith(
        lastStatus: '상태 확인 실패',
        lastCheckedAt: DateTime.now(),
        failureCount: item.failureCount + 1,
      );
      await _replace(next);
      return next;
    }
  }

  Future<void> checkDueItems() async {
    if (!AppConfig.hasApiKey) {
      return;
    }
    for (final item in await list()) {
      if (!item.active || item.completed) {
        continue;
      }
      final last = item.lastCheckedAt;
      if (last != null &&
          DateTime.now().difference(last) < alertCheckCooldown) {
        continue;
      }
      await checkNow(item);
    }
  }

  Future<void> _replace(LoanAlertItem item) async =>
      _save((await list()).map((e) => e.id == item.id ? item : e).toList());
  Future<void> _save(List<LoanAlertItem> items) async =>
      (await SharedPreferences.getInstance()).setStringList(
        _key,
        items.map((e) => e.encode()).toList(),
      );

  Future<void> _notify(LoanAlertItem item) async {
    await loanAlertNotifications.show(
      id: item.id.hashCode,
      title: '『${item.title}』 대출 가능 확인',
      body: '${item.libraryName}에서 대출 가능한 상태로 확인되었습니다.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'loan_alerts',
          '대출 가능 알림',
          channelDescription: '도서관 정보나루 대출 가능 상태 확인 알림',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void loanAlertDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await LoanAlertService().checkDueItems();
    return true;
  });
}
