// lib/features/notifications/providers/monitoring_alert_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/monitoring_alert.dart';
import '../../../services/monitoring_alert_service.dart';

class MonitoringAlertState {
  final List<MonitoringAlert> alerts;
  final bool isLoading;
  final String? error;

  const MonitoringAlertState({
    this.alerts = const [],
    this.isLoading = false,
    this.error,
  });

  MonitoringAlertState copyWith({
    List<MonitoringAlert>? alerts,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => MonitoringAlertState(
        alerts: alerts ?? this.alerts,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );

  int get unreadCount => alerts.where((a) => a.isUnread).length;
}

class MonitoringAlertNotifier extends StateNotifier<MonitoringAlertState> {
  MonitoringAlertNotifier() : super(const MonitoringAlertState(isLoading: true)) {
    load();
  }

  final _service = MonitoringAlertService();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final alerts = await _service.getAlerts();
      state = state.copyWith(alerts: alerts, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Gagal memuat riwayat notifikasi.');
    }
  }

  /// Dipanggil saat halaman riwayat dibuka, atau saat sebuah alert di-tap.
  Future<void> markAsRead(String alertId) async {
    await _service.markAsRead(alertId);
    state = state.copyWith(
      alerts: [
        for (final a in state.alerts)
          if (a.id == alertId) _withReadNow(a) else a,
      ],
    );
  }

  /// Dipanggil saat notifikasi push di-tap (dari luar aplikasi).
  Future<void> markAsClicked(String alertId) async {
    await _service.markAsClicked(alertId);
    await load();
  }

  Future<void> markAllAsRead() async {
    await _service.markAllAsRead();
    await load();
  }

  MonitoringAlert _withReadNow(MonitoringAlert a) => MonitoringAlert(
        id: a.id,
        userId: a.userId,
        goalId: a.goalId,
        ruleCode: a.ruleCode,
        title: a.title,
        body: a.body,
        deepLink: a.deepLink,
        status: a.status,
        meta: a.meta,
        sentAt: a.sentAt,
        clickedAt: a.clickedAt,
        readAt: DateTime.now(),
        createdAt: a.createdAt,
      );
}

final monitoringAlertProvider =
    StateNotifierProvider.autoDispose<MonitoringAlertNotifier, MonitoringAlertState>(
  (ref) => MonitoringAlertNotifier(),
);
