import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'supabase_service.dart';

/// High-importance channel so foreground OTP banners pop as heads-up.
const AndroidNotificationChannel _kChannel = AndroidNotificationChannel(
  'company_registration',
  'Company Registrations',
  description: 'New-company registration approval OTPs',
  importance: Importance.high,
);
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Background message handler. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Notification is shown by the system tray automatically; nothing to do here
  // for the registration-OTP push, but the handler must exist to be registered.
  debugPrint('FCM background message: ${message.messageId}');
}

/// Draws a heads-up banner for a message received while the app is foregrounded.
void _showForegroundBanner(RemoteMessage message) {
  final n = message.notification;
  final otp = message.data['otp'];
  final title = n?.title ?? message.data['company'] ?? 'New company registration';
  final body =
      n?.body ?? (otp != null ? 'Approval OTP: $otp' : 'Tap to review.');
  _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannel.id,
        _kChannel.name,
        channelDescription: _kChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );
}

/// Thin wrapper around Firebase Cloud Messaging.
///
/// Everything is guarded: if Firebase has not been configured yet (no
/// google-services.json / GoogleService-Info.plist), initialization fails
/// silently and the rest of the app keeps working. Push is only required for
/// the new-company registration OTP flow on the owner/super-admin device.
class PushService {
  static bool _ready = false;

  /// Initializes Firebase + messaging. Safe to call unconditionally from main.
  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission();

      // Local notifications — lets us draw a heads-up banner for messages that
      // arrive while the app is in the FOREGROUND (Android suppresses FCM's own
      // tray banner then). Background/terminated banners are shown by the OS.
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_kChannel);
      FirebaseMessaging.onMessage.listen(_showForegroundBanner);

      _ready = true;
    } catch (e) {
      // Firebase not configured on this platform yet — push features are simply
      // unavailable until google-services.json / APNs are added.
      debugPrint('PushService.init skipped: $e');
    }
  }

  /// Returns this device's FCM token, or null if messaging is unavailable.
  static Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('PushService.token failed: $e');
      return null;
    }
  }

  /// Registers this device as an owner/super-admin recipient for new-company
  /// registration OTPs. Returns true if a token was successfully registered.
  static Future<bool> registerAsSuperAdmin({String? label}) async {
    final t = await token();
    if (t == null) return false;
    try {
      await SupabaseService.registerSuperAdminDevice(t, label: label);
      return true;
    } catch (e) {
      debugPrint('registerAsSuperAdmin failed: $e');
      return false;
    }
  }

  /// Listens for foreground registration-OTP pushes and surfaces the OTP +
  /// company name to the caller (so the owner dashboard can show a dialog while
  /// the app is open). Returns a subscription to cancel on dispose, or null if
  /// messaging is unavailable. Only fires for the registration-OTP data type.
  static StreamSubscription<RemoteMessage>? listenRegistrationOtp(
    void Function(String otp, String company) onOtp,
  ) {
    if (!_ready) return null;
    return FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'company_registration_otp') {
        onOtp(
          data['otp']?.toString() ?? '',
          data['company']?.toString() ?? 'A new company',
        );
      }
    });
  }
}
