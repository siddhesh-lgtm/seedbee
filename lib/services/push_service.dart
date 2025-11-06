import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:home_widget/home_widget.dart';

import '../firebase_options.dart';

// Background handler must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _refreshWidgetFromRealtimeDB();
}

class PushService {
  static const String widgetTopic = 'widget_updates';
  static const String notesTopic = 'notes_updates';

  Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // Request permissions on Android 13+ and iOS (no-op otherwise).
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ensure background handler is registered.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Subscribe to topic for widget updates.
    await messaging.subscribeToTopic(widgetTopic);
    await messaging.subscribeToTopic(notesTopic);

    // Handle foreground messages as well (quick refresh when user is active).
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _refreshWidgetFromRealtimeDB();
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _refreshWidgetFromRealtimeDB();
    });
  }
}

Future<void> _refreshWidgetFromRealtimeDB() async {
  try {
    // Adjust URL if your database location is not default; keep path consistent
    // with where we broadcast updates from the app.
    final url = Uri.parse(
        'https://shared-notes-app-2a464-default-rtdb.firebaseio.com/notes/widget.json');
    final client = HttpClient();
    final req = await client.getUrl(url);
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    if (resp.statusCode == 200 && body.isNotEmpty) {
      final map = jsonDecode(body);
      if (map is Map) {
        final display = (map['display_text']?.toString() ?? '').trim();
        final id = (map['selected_note_id']?.toString() ?? '').trim();
        final imagePath = (map['image_path']?.toString() ?? '').trim();
        if (display.isNotEmpty) {
          await HomeWidget.saveWidgetData('note_text', display);
          if (id.isNotEmpty) {
            await HomeWidget.saveWidgetData('note_id', id);
          }
          await HomeWidget.saveWidgetData('note_image', imagePath);
          await HomeWidget.updateWidget(androidName: 'NoteWidgetProvider');
        }
      }
    }
  } catch (_) {
    // Swallow errors; background updates should be best-effort.
  }
}
