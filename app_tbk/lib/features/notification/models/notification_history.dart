// lib/models/notification_history.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

// ==================== MODEL ====================
class NotificationHistory {
  final int? id;
  final String title;
  final String body;
  final String type; // 'CLASS', 'EXAM', 'REMINDER', 'EXAM_ADVANCE'
  final DateTime sentAt;
  final bool isRead;
  final Map<String, dynamic>? payload;

  NotificationHistory({
    this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.sentAt,
    this.isRead = false,
    this.payload,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type,
      'sentAt': sentAt.millisecondsSinceEpoch,
      'isRead': isRead ? 1 : 0,
      'payload': payload != null ? jsonEncode(payload) : null,
    };
  }

  factory NotificationHistory.fromMap(Map<String, dynamic> map) {
    return NotificationHistory(
      id: map['id'],
      title: map['title'],
      body: map['body'],
      type: map['type'],
      sentAt: DateTime.fromMillisecondsSinceEpoch(map['sentAt']),
      isRead: map['isRead'] == 1,
      payload: map['payload'] != null
          ? jsonDecode(map['payload']) as Map<String, dynamic>
          : null,
    );
  }

  NotificationHistory copyWith({
    int? id,
    String? title,
    String? body,
    String? type,
    DateTime? sentAt,
    bool? isRead,
    Map<String, dynamic>? payload,
  }) {
    return NotificationHistory(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      payload: payload ?? this.payload,
    );
  }

  // Helper getters
  String get typeEmoji {
    switch (type) {
      case 'CLASS':
        return '📘';
      case 'EXAM':
        return '🧾';
      case 'REMINDER':
        return '⏰';
      case 'EXAM_ADVANCE':
        return '📅';
      default:
        return '🔔';
    }
  }

  String get typeLabel {
    switch (type) {
      case 'CLASS':
        return 'Lịch học';
      case 'EXAM':
        return 'Lịch thi';
      case 'REMINDER':
        return 'Nhắc nhở';
      case 'EXAM_ADVANCE':
        return 'Thông báo thi';
      default:
        return 'Thông báo';
    }
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(sentAt);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';

    return '${sentAt.day}/${sentAt.month}/${sentAt.year}';
  }
}

// ==================== DATABASE SERVICE ====================
class NotificationHistoryDatabase {
  static final NotificationHistoryDatabase _instance =
  NotificationHistoryDatabase._internal();
  static NotificationHistoryDatabase get instance => _instance;
  NotificationHistoryDatabase._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'notification_history.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notification_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        type TEXT NOT NULL,
        sentAt INTEGER NOT NULL,
        isRead INTEGER NOT NULL DEFAULT 0,
        payload TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sentAt ON notification_history(sentAt DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_type ON notification_history(type)
    ''');
  }

  // ==================== CRUD OPERATIONS ====================

  Future<int> insert(NotificationHistory notification) async {
    final db = await database;
    final id = await db.insert(
      'notification_history',
      notification.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    print('💾 Saved notification to history: ${notification.title}');
    return id;
  }

  Future<List<NotificationHistory>> getAll({int? limit}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notification_history',
      orderBy: 'sentAt DESC',
      limit: limit,
    );

    return List.generate(maps.length, (i) {
      return NotificationHistory.fromMap(maps[i]);
    });
  }

  Future<List<NotificationHistory>> getByType(String type) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notification_history',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'sentAt DESC',
    );

    return List.generate(maps.length, (i) {
      return NotificationHistory.fromMap(maps[i]);
    });
  }

  Future<List<NotificationHistory>> getUnread() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notification_history',
      where: 'isRead = ?',
      whereArgs: [0],
      orderBy: 'sentAt DESC',
    );

    return List.generate(maps.length, (i) {
      return NotificationHistory.fromMap(maps[i]);
    });
  }

  Future<int> getUnreadCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notification_history WHERE isRead = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> markAsRead(int id) async {
    final db = await database;
    await db.update(
      'notification_history',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllAsRead() async {
    final db = await database;
    await db.update(
      'notification_history',
      {'isRead': 1},
    );
  }

  Future<void> delete(int id) async {
    final db = await database;
    await db.delete(
      'notification_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteOlderThan(int days) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    await db.delete(
      'notification_history',
      where: 'sentAt < ?',
      whereArgs: [cutoffDate.millisecondsSinceEpoch],
    );
    print('🗑️ Deleted notifications older than $days days');
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete('notification_history');
    print('🗑️ Deleted all notification history');
  }

  Future<Map<String, int>> getStatistics() async {
    final db = await database;

    final total = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM notification_history'),
    ) ?? 0;

    final unread = await getUnreadCount();

    final classCount = Sqflite.firstIntValue(
      await db.rawQuery(
          'SELECT COUNT(*) FROM notification_history WHERE type = "CLASS"'
      ),
    ) ?? 0;

    final examCount = Sqflite.firstIntValue(
      await db.rawQuery(
          'SELECT COUNT(*) FROM notification_history WHERE type = "EXAM"'
      ),
    ) ?? 0;

    final reminderCount = Sqflite.firstIntValue(
      await db.rawQuery(
          'SELECT COUNT(*) FROM notification_history WHERE type = "REMINDER"'
      ),
    ) ?? 0;

    return {
      'total': total,
      'unread': unread,
      'class': classCount,
      'exam': examCount,
      'reminder': reminderCount,
    };
  }

  Future<List<NotificationHistory>> getByDateRange(
      DateTime start,
      DateTime end
      ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notification_history',
      where: 'sentAt BETWEEN ? AND ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'sentAt DESC',
    );

    return List.generate(maps.length, (i) {
      return NotificationHistory.fromMap(maps[i]);
    });
  }
}