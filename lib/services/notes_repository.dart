import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

class NotesRepository {
  final DatabaseReference _root =
      FirebaseDatabase.instance.ref('notes/shared');

  NotesRepository() {
    // Enable Firebase offline persistence and keep this path synced
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    _root.keepSynced(true);
  }

  Stream<List<Note>> notesStream() {
    return _root.onValue.map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        final list = val.values
            .whereType<Map>()
            .map((m) => Note.fromMap(m))
            .toList();
        list.sort((a, b) {
          // pinned first, then updatedAt desc
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return (b.updatedAt).compareTo(a.updatedAt);
        });
        return list;
      }
      return <Note>[];
    });
  }

  Future<void> upsertNote(Note note) async {
    note.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _root.child(note.id).set(note.toMap());
    await _cacheLastNoteTitle(note.title);
  }

  Future<void> deleteNote(String id) async {
    await _root.child(id).remove();
  }

  Future<void> _cacheLastNoteTitle(String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_note_title', title);
  }
}
