import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        ErrorDescription,
        FlutterError,
        FlutterErrorDetails,
        TargetPlatform,
        defaultTargetPlatform,
        kIsWeb,
        visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/app_locale.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart';
import 'notification_provider.dart';

const _notificationChannelId = 'footwear_business_activity';
const _notificationHistoryPrefix = 'android_business_alert_ids_v1';
const _maxRememberedNotificationIds = 100;

@visibleForTesting
List<NotificationModel> foregroundNotificationCandidates({
  required Iterable<NotificationModel> notifications,
  required Set<String> deliveredNotificationIds,
  required DateTime sessionStartedAt,
}) => notifications
    .where(
      (notification) =>
          !notification.sourceDeleted &&
          !notification.read &&
          !deliveredNotificationIds.contains(notification.id) &&
          notification.createdAt.toDate().isAfter(sessionStartedAt),
    )
    .toList(growable: false);

abstract interface class AndroidNotificationClient {
  Future<bool> notificationsEnabled(AppLocale locale);

  Future<bool> requestNotificationsPermission(AppLocale locale);

  Future<void> deliverNewEntries({
    required String userId,
    required String tenantId,
    required Iterable<NotificationModel> notifications,
    required DateTime sessionStartedAt,
    required AppLocale locale,
  });
}

final androidNotificationClientProvider = Provider<AndroidNotificationClient>(
  (ref) => LocalAndroidNotificationClient(),
);

class AndroidNotificationPermissionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    final locale = ref.watch(appLocaleProvider);
    if (!_isAndroid) return Future.value(false);
    return ref
        .read(androidNotificationClientProvider)
        .notificationsEnabled(locale);
  }

  Future<bool> request() async {
    if (!_isAndroid) return false;
    state = const AsyncLoading();
    final locale = ref.read(appLocaleProvider);
    final result = await AsyncValue.guard(
      () => ref
          .read(androidNotificationClientProvider)
          .requestNotificationsPermission(locale),
    );
    state = result;
    return result.requireValue;
  }
}

final androidNotificationPermissionProvider =
    AsyncNotifierProvider<AndroidNotificationPermissionNotifier, bool>(
      AndroidNotificationPermissionNotifier.new,
    );

final androidNotificationObserverProvider =
    NotifierProvider<AndroidNotificationObserver, void>(
      AndroidNotificationObserver.new,
    );

class AndroidNotificationObserver extends Notifier<void> {
  String? _scopeKey;
  DateTime? _sessionStartedAt;

  @override
  void build() {
    if (!_isAndroid) {
      _resetScope();
      return;
    }

    final tenantId = ref.watch(notificationTenantScopeProvider);
    final user = ref.watch(authUserProvider).value;
    if (tenantId == null ||
        user == null ||
        user.id.trim().isEmpty ||
        notificationTenantIdFor(user) != tenantId) {
      _resetScope();
      return;
    }

    final scopeKey = '${user.id}:$tenantId';
    if (_scopeKey != scopeKey) {
      _scopeKey = scopeKey;
      _sessionStartedAt = DateTime.now();
    }

    final permission = ref.watch(androidNotificationPermissionProvider);
    if (permission.value != true) return;

    final feed = ref.watch(notificationsProvider(tenantId));
    final shops = ref.watch(activeNotificationShopIdsProvider(tenantId));
    if (feed.hasError || shops.hasError || !feed.hasValue || !shops.hasValue) {
      return;
    }

    final visible = visibleNotificationState(feed, shops).value;
    final sessionStartedAt = _sessionStartedAt;
    if (visible == null || sessionStartedAt == null) return;

    unawaited(
      ref
          .read(androidNotificationClientProvider)
          .deliverNewEntries(
            userId: user.id,
            tenantId: tenantId,
            notifications: visible,
            sessionStartedAt: sessionStartedAt,
            locale: ref.read(appLocaleProvider),
          )
          .catchError((Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'Android notification delivery',
                context: ErrorDescription(
                  'while delivering a tenant-scoped local notification',
                ),
              ),
            );
          }),
    );
  }

  void _resetScope() {
    _scopeKey = null;
    _sessionStartedAt = null;
  }
}

class LocalAndroidNotificationClient implements AndroidNotificationClient {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, Future<void>> _deliveryQueues = {};
  Future<void>? _initialization;

  @override
  Future<bool> notificationsEnabled(AppLocale locale) async {
    if (!_isAndroid) return false;
    final android = await _androidPlugin(locale);
    return await android.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestNotificationsPermission(AppLocale locale) async {
    if (!_isAndroid) return false;
    final android = await _androidPlugin(locale);
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> deliverNewEntries({
    required String userId,
    required String tenantId,
    required Iterable<NotificationModel> notifications,
    required DateTime sessionStartedAt,
    required AppLocale locale,
  }) {
    final scope = '$userId:$tenantId';
    final previous = _deliveryQueues[scope] ?? Future<void>.value();
    final next = previous.then(
      (_) => _deliver(
        userId: userId,
        tenantId: tenantId,
        notifications: notifications.toList(growable: false),
        sessionStartedAt: sessionStartedAt,
        locale: locale,
      ),
      onError: (Object _, StackTrace _) => _deliver(
        userId: userId,
        tenantId: tenantId,
        notifications: notifications.toList(growable: false),
        sessionStartedAt: sessionStartedAt,
        locale: locale,
      ),
    );
    _deliveryQueues[scope] = next;
    return next.whenComplete(() {
      if (identical(_deliveryQueues[scope], next)) {
        _deliveryQueues.remove(scope);
      }
    });
  }

  Future<void> _deliver({
    required String userId,
    required String tenantId,
    required List<NotificationModel> notifications,
    required DateTime sessionStartedAt,
    required AppLocale locale,
  }) async {
    if (!await notificationsEnabled(locale)) return;

    final preferences = await SharedPreferences.getInstance();
    final historyKey = '$_notificationHistoryPrefix:$userId:$tenantId';
    final deliveredIds =
        preferences.getStringList(historyKey)?.toSet() ?? <String>{};
    deliveredIds.addAll(
      notifications
          .where(
            (notification) =>
                !notification.createdAt.toDate().isAfter(sessionStartedAt),
          )
          .map((notification) => notification.id),
    );
    await preferences.setStringList(
      historyKey,
      _boundedNotificationIds(deliveredIds),
    );

    for (final notification in foregroundNotificationCandidates(
      notifications: notifications,
      deliveredNotificationIds: deliveredIds,
      sessionStartedAt: sessionStartedAt,
    )) {
      await _plugin.show(
        id: _notificationId(notification.id),
        title: trRead(
          notification.type == 'invoice'
              ? 'notification_new_invoice'
              : 'notification_new_transaction',
          locale,
        ),
        body: notification.shopName.trim().isEmpty
            ? trRead('notification_center', locale)
            : notification.shopName.trim(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _notificationChannelId,
            trRead('android_notification_channel_name', locale),
            channelDescription: trRead(
              'android_notification_channel_description',
              locale,
            ),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            visibility: NotificationVisibility.private,
            playSound: false,
            onlyAlertOnce: true,
          ),
        ),
      );
      deliveredIds.add(notification.id);
      await preferences.setStringList(
        historyKey,
        _boundedNotificationIds(deliveredIds),
      );
    }
  }

  Future<AndroidFlutterLocalNotificationsPlugin> _androidPlugin(
    AppLocale locale,
  ) async {
    await (_initialization ??= _initialize());
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      throw StateError('android_notifications_unavailable');
    }
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _notificationChannelId,
        trRead('android_notification_channel_name', locale),
        description: trRead('android_notification_channel_description', locale),
        importance: Importance.defaultImportance,
      ),
    );
    return android;
  }

  Future<void> _initialize() async {
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    if (initialized != true) {
      throw StateError('android_notifications_initialization_failed');
    }
  }

  List<String> _boundedNotificationIds(Set<String> ids) {
    final orderedIds = ids.toList(growable: false);
    return orderedIds.length <= _maxRememberedNotificationIds
        ? orderedIds
        : orderedIds.sublist(orderedIds.length - _maxRememberedNotificationIds);
  }

  int _notificationId(String documentId) {
    var hash = 0x811c9dc5;
    for (final unit in documentId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
