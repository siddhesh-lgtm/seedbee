import 'package:firebase_database/firebase_database.dart';
import 'package:home_widget/home_widget.dart';

class WidgetSyncService {
  DatabaseReference get _ref => FirebaseDatabase.instance.ref('notes/widget');

  void start() {
    // Keep the small widget path in sync for offline resilience
    _ref.keepSynced(true);
    _ref.onValue.listen((event) async {
      final val = event.snapshot.value;
      if (val is Map) {
        final data = Map<dynamic, dynamic>.from(val);
        final String display = (data['display_text']?.toString() ?? '').trim();
        final String id = (data['selected_note_id']?.toString() ?? '').trim();
        final String imagePath = (data['image_path']?.toString() ?? '').trim();
        final int? bg = (data['background'] as num?)?.toInt();
        final int? textColor = (data['text_color'] as num?)?.toInt();
        if (display.isNotEmpty) {
          await HomeWidget.saveWidgetData('note_text', display);
          if (id.isNotEmpty) {
            await HomeWidget.saveWidgetData('note_id', id);
          }
          await HomeWidget.saveWidgetData('note_image', imagePath);
          if (bg != null) {
            await HomeWidget.saveWidgetData('note_bg', bg);
          }
          if (textColor != null) {
            await HomeWidget.saveWidgetData('note_text_color', textColor);
          }
          await HomeWidget.updateWidget(androidName: 'NoteWidgetProvider');
        }
      }
    });
  }
}
