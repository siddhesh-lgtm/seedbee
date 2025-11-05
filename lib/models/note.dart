
class Note {
  final String id;
  String title;
  String category; // e.g., Work, Personal, Projects
  bool pinned;
  // Rich text is stored as Quill Delta JSON string
  String deltaJson;
  List<String> imagePaths; // local image file paths
  int? backgroundColor; // ARGB color for note background
  int? textColor; // ARGB color for text
  bool bold;
  bool italic;
  bool underline;
  bool strike;
  int createdAt;
  int updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.category,
    required this.pinned,
    required this.deltaJson,
    List<String>? imagePaths,
    this.backgroundColor,
    this.textColor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    int? createdAt,
    int? updatedAt,
  })  : imagePaths = imagePaths ?? <String>[],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category,
        'pinned': pinned,
        'deltaJson': deltaJson,
        'imagePaths': imagePaths,
        'backgroundColor': backgroundColor,
        'textColor': textColor,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'strike': strike,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Note.fromMap(Map<dynamic, dynamic> map) {
    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      category: map['category'] as String? ?? 'General',
      pinned: map['pinned'] as bool? ?? false,
      deltaJson: map['deltaJson'] as String? ?? '[{"insert":"\n"}]',
      imagePaths: (map['imagePaths'] as List?)?.cast<String>() ?? <String>[],
      backgroundColor: (map['backgroundColor'] as num?)?.toInt(),
      textColor: (map['textColor'] as num?)?.toInt(),
      bold: map['bold'] as bool? ?? false,
      italic: map['italic'] as bool? ?? false,
      underline: map['underline'] as bool? ?? false,
      strike: map['strike'] as bool? ?? false,
      createdAt: (map['createdAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }
}
