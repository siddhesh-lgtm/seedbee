import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../services/notes_repository.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  final bool isNew;
  const NoteEditorScreen({super.key, required this.note, this.isNew = false});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late Note _note;
  final _repo = NotesRepository();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _category = 'General';
  // Removed background and text color pickers per request.
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _titleController.text = _note.title;
    _category = _note.category;
    _bodyController.text = _deltaToPlainText(_note.deltaJson);
    _bodyController.addListener(_onBodyChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    if (_undoStack.isEmpty || _undoStack.last != _bodyController.text) {
      _undoStack.add(_bodyController.text);
      if (_undoStack.length > 50) _undoStack.removeAt(0);
    }
  }

  Future<void> _save() async {
    final deltaJson = _plainTextToDeltaJson(_bodyController.text);
    _note
      ..title = _titleController.text.trim()
      ..category = _category
      ..deltaJson = deltaJson
      ..textColor = _note.textColor
      ..bold = _note.bold
      ..italic = _note.italic
      ..underline = _note.underline
      ..strike = _note.strike;
    await _repo.upsertNote(_note);
    // If this is the note currently selected for the widget, also refresh the
    // shared widget payload so Cloud Functions can fan out a push immediately.
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedId = prefs.getString('selected_note_id');
      if (selectedId == _note.id) {
        final text = _bodyController.text.trim();
        final display = (_titleController.text.trim().isNotEmpty
                ? '${_titleController.text.trim()}\n\n'
                : '') +
            text;
        final img = _note.imagePaths.isNotEmpty ? _note.imagePaths.first : '';
        final ref = FirebaseDatabase.instance.ref('notes/widget');
        await ref.set({
          'selected_note_id': _note.id,
          'display_text': display.isEmpty ? '(Empty note)' : display,
          'image_path': img,
          'updated_at': ServerValue.timestamp,
        });
      }
    } catch (_) {}
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

  String _plainTextToDeltaJson(String text) {
    final content = text.endsWith('\n') ? text : '$text\n';
    return jsonEncode([
      {
        'insert': content,
      }
    ]);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    _note.imagePaths.add(file.path);
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _deleteNote() async {
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
    if (ok == true) {
      await NotesRepository().deleteNote(_note.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _applyFormat(String before, [String after = '']) {
    final sel = _bodyController.selection;
    final text = _bodyController.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final selected = text.substring(start, end);
    final formatted = '$before$selected${after.isEmpty ? before : after}';
    final newText = text.replaceRange(start, end, formatted);
    _bodyController.text = newText;
    _bodyController.selection = TextSelection.collapsed(offset: start + formatted.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: 'Title',
            border: InputBorder.none,
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteNote,
          ),
          IconButton(
            icon: const Icon(Icons.push_pin_outlined),
            tooltip: 'Toggle pin',
            onPressed: () async {
              _note.pinned = !_note.pinned;
              await _save();
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Attach image',
            icon: const Icon(Icons.image_outlined),
            onPressed: _pickImage,
          ),
          IconButton(
            icon: const Icon(Icons.widgets_outlined),
            tooltip: 'Show in Widget',
            onPressed: () async {
              final text = _bodyController.text.trim();
              final display = (_titleController.text.trim().isNotEmpty
                      ? '${_titleController.text.trim()}\n\n'
                      : '') +
                  text;
              await HomeWidget.saveWidgetData(
                  'note_text', display.isEmpty ? '(Empty note)' : display);
              await HomeWidget.saveWidgetData('note_id', _note.id);
              final img = _note.imagePaths.isNotEmpty ? _note.imagePaths.first : '';
              await HomeWidget.saveWidgetData('note_image', img);
              // No longer saving background or text color into the widget store.
              // Broadcast to all devices
              final ref = FirebaseDatabase.instance.ref('notes/widget');
              await ref.set({
                'selected_note_id': _note.id,
                'display_text': display.isEmpty ? '(Empty note)' : display,
                'image_path': img,
                // Colors removed; rely on default widget styling
                'updated_at': ServerValue.timestamp,
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('selected_note_id', _note.id);
              await HomeWidget.updateWidget(androidName: 'NoteWidgetProvider');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Widget updated')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _save();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox.shrink(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bodyController,
                        maxLines: null,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: _note.bold ? FontWeight.bold : FontWeight.normal,
                          fontStyle: _note.italic ? FontStyle.italic : FontStyle.normal,
                          decoration: TextDecoration.combine([
                            if (_note.underline) TextDecoration.underline,
                            if (_note.strike) TextDecoration.lineThrough,
                          ]),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Start typing your note...',
                          border: InputBorder.none,
                          isCollapsed: false,
                        ),
                      ),
                    ),
                    if (_note.imagePaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _note.imagePaths.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final p = _note.imagePaths[i];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(File(p), width: 80, height: 80, fit: BoxFit.cover),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
