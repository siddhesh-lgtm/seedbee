import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/notes_repository.dart';
import 'note_editor_screen.dart';

const kDefaultCategories = [
  'All',
  'General',
  'Work',
  'Personal',
  'Projects',
  'Ideas',
];

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  final _repo = NotesRepository();
  String _query = '';
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New note',
            onPressed: _newNote,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search notes...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _category,
                  items: kDefaultCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v ?? 'All'),
                )
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: _repo.notesStream(),
              builder: (context, snap) {
                final notes = (snap.data ?? <Note>[]) // filter by category
                    .where((n) => _category == 'All' || n.category == _category)
                    .where((n) => _query.isEmpty ||
                        (n.title.toLowerCase().contains(_query.toLowerCase())))
                    .toList();

                // Avoid indefinite spinner; show empty state when no data
                if (notes.isEmpty) {
                  return const Center(child: Text('No notes yet'));
                }

                // group by pinned for visual separation
                final pinned = notes.where((n) => n.pinned).toList();
                final others = notes.where((n) => !n.pinned).toList();

                return ListView(
                  children: [
                    if (pinned.isNotEmpty)
                      _SectionHeader(title: 'Pinned (${pinned.length})'),
                    ...pinned.map(_tileFor),
                    if (others.isNotEmpty)
                      _SectionHeader(title: 'All Notes (${others.length})'),
                    ...others.map(_tileFor),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newNote,
        icon: const Icon(Icons.note_add),
        label: const Text('New Note'),
      ),
    );
  }

  Widget _tileFor(Note n) {
    return ListTile(
      leading: Icon(n.pinned ? Icons.push_pin : Icons.note_outlined),
      title: Text(
        n.title.isEmpty ? '(Untitled)' : n.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${n.category} · ' 
          '${DateTime.fromMillisecondsSinceEpoch(n.updatedAt)}'),
      trailing: IconButton(
        icon: Icon(n.pinned ? Icons.push_pin : Icons.push_pin_outlined),
        onPressed: () async {
          final updated = Note(
            id: n.id,
            title: n.title,
            category: n.category,
            pinned: !n.pinned,
            deltaJson: n.deltaJson,
            imagePaths: n.imagePaths,
            createdAt: n.createdAt,
            updatedAt: n.updatedAt,
          );
          await _repo.upsertNote(updated);
        },
      ),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NoteEditorScreen(note: n),
        ));
      },
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: const Text('Show in Widget'),
                  onTap: () => Navigator.pop(ctx, 'widget'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (action == 'widget') {
          await _setAsWidget(n);
        } else if (action == 'delete') {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete note?'),
              content: const Text('This will remove the note for everyone.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
              ],
            ),
          );
          if (ok == true) await _repo.deleteNote(n.id);
        }
      },
    );
  }

  Future<void> _newNote() async {
    final id = const Uuid().v4();
    // Minimal empty Quill delta for a blank note
    final emptyDeltaJson = jsonEncode([
      {'insert': '\n'}
    ]);
    final note = Note(
      id: id,
      title: '',
      category: 'General',
      pinned: false,
      deltaJson: emptyDeltaJson,
    );
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(note: note, isNew: true),
    ));
  }

  Future<void> _setAsWidget(Note n) async {
    final text = _deltaToPlainText(n.deltaJson).trim();
    final display = (n.title.isNotEmpty ? '${n.title}\n\n' : '') + text;
    await HomeWidget.saveWidgetData('note_text', display.isEmpty ? '(Empty note)' : display);
    await HomeWidget.saveWidgetData('note_id', n.id);
    // Also pass image and background
    final img = n.imagePaths.isNotEmpty ? n.imagePaths.first : '';
    await HomeWidget.saveWidgetData('note_image', img);
    if (n.backgroundColor != null) {
      await HomeWidget.saveWidgetData('note_bg', n.backgroundColor);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_note_id', n.id);
    // Broadcast selection to all users
    final ref = FirebaseDatabase.instance.ref('notes/widget');
    await ref.set({
      'selected_note_id': n.id,
      'display_text': display.isEmpty ? '(Empty note)' : display,
      'image_path': img,
      'background': n.backgroundColor,
      'updated_at': ServerValue.timestamp,
    });
    await HomeWidget.updateWidget(androidName: 'NoteWidgetProvider');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Widget updated with selected note')),
    );
  }

  String _deltaToPlainText(String raw) {
    try {
      if (raw.trim().isEmpty) return '';
      final list = jsonDecode(raw) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in list) {
        final m = Map<String, dynamic>.from(op as Map);
        final ins = m['insert'];
        if (ins is String) buffer.write(ins);
      }
      return buffer.toString();
    } catch (_) {
      return '';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
