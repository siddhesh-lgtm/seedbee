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
  final List<Color> _bgChoices = [
    Colors.white,
    const Color(0xFFFFF8E1),
    const Color(0xFFE3F2FD),
    const Color(0xFFE8F5E9),
    const Color(0xFFFCE4EC),
    const Color(0xFFFFEBEE),
  ];
  final List<Color> _textColors = [
    Colors.black,
    Colors.blueGrey,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
  ];
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
              if (_note.backgroundColor != null) {
                await HomeWidget.saveWidgetData('note_bg', _note.backgroundColor);
              }
              if (_note.textColor != null) {
                await HomeWidget.saveWidgetData('note_text_color', _note.textColor);
              }
              // Broadcast to all devices
              final ref = FirebaseDatabase.instance.ref('notes/widget');
              await ref.set({
                'selected_note_id': _note.id,
                'display_text': display.isEmpty ? '(Empty note)' : display,
                'image_path': img,
                'background': _note.backgroundColor,
                'text_color': _note.textColor,
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
          // Background + simple formatting + undo/redo
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                for (final c in _bgChoices)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () async {
                        _note.backgroundColor = c.value;
                        await _save();
                        if (mounted) setState(() {});
                      },
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: c,
                        child: (_note.backgroundColor == c.value)
                            ? const Icon(Icons.check, size: 16)
                            : null,
                      ),
                  ),
                ),
                const SizedBox(width: 12),
                // Text color options
                for (final c in _textColors)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () async {
                        _note.textColor = c.value;
                        await _save();
                        if (mounted) setState(() {});
                      },
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: c,
                        child: (_note.textColor == c.value)
                            ? const Icon(Icons.radio_button_checked, size: 12, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo),
                  onPressed: () {
                    if (_undoStack.length >= 2) {
                      final cur = _undoStack.removeLast();
                      _redoStack.add(cur);
                      final prev = _undoStack.last;
                      _bodyController.text = prev;
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Redo',
                  icon: const Icon(Icons.redo),
                  onPressed: () {
                    if (_redoStack.isNotEmpty) {
                      final next = _redoStack.removeLast();
                      _bodyController.text = next;
                      _undoStack.add(next);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Bold',
                  icon: const Icon(Icons.format_bold),
                  onPressed: () async {
                    _note.bold = !_note.bold;
                    await _save();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Italic',
                  icon: const Icon(Icons.format_italic),
                  onPressed: () async {
                    _note.italic = !_note.italic;
                    await _save();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Underline',
                  icon: const Icon(Icons.format_underline),
                  onPressed: () async {
                    _note.underline = !_note.underline;
                    await _save();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Strikethrough',
                  icon: const Icon(Icons.format_strikethrough),
                  onPressed: () async {
                    _note.strike = !_note.strike;
                    await _save();
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Bullet',
                  icon: const Icon(Icons.format_list_bulleted),
                  onPressed: () {
                    final t = _bodyController.text;
                    final sel = _bodyController.selection.start;
                    final before = t.substring(0, sel);
                    final after = t.substring(sel);
                    _bodyController.text = '$before- $after';
                    _bodyController.selection = TextSelection.collapsed(offset: sel + 2);
                  },
                ),
                IconButton(
                  tooltip: 'Numbered',
                  icon: const Icon(Icons.format_list_numbered),
                  onPressed: () {
                    final t = _bodyController.text;
                    final sel = _bodyController.selection.start;
                    final before = t.substring(0, sel);
                    final after = t.substring(sel);
                    _bodyController.text = '${before}1. $after';
                    _bodyController.selection = TextSelection.collapsed(offset: sel + 3);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Color(_note.backgroundColor ?? Colors.white.value),
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      style: TextStyle(
                        color: Color(_note.textColor ?? Colors.black.value),
                        fontWeight: _note.bold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: _note.italic ? FontStyle.italic : FontStyle.normal,
                        decoration: TextDecoration.combine([
                          if (_note.underline) TextDecoration.underline,
                          if (_note.strike) TextDecoration.lineThrough,
                        ]),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Start typing your note...',
                        border: OutlineInputBorder(),
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
        ],
      ),
    );
  }
}
