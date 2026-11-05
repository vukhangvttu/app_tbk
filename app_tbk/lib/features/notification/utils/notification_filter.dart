import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// =====================================================================
/// BỘ LỌC THÔNG BÁO
/// Đặt tại: lib/features/notification/utils/notification_filter.dart
///
/// Lọc phía client trên các thông báo ĐÃ TẢI. Muốn lọc chính xác trên toàn bộ
/// lịch sử, cần thêm tham số from/to/type/is_read/subject/q ở API (xem hướng dẫn).
/// =====================================================================

/// Giao diện tối thiểu bộ lọc cần. NotificationHistory chỉ cần `implements` nó.
abstract interface class FilterableNotification {
  String get title;
  String get body;
  String get type;
  DateTime get timestamp;
  bool get is_read;
  String? get subject; // tên môn nếu server trả về, ngược lại null
}

// ---------------------------------------------------------------------
// ENUM + NHÃN
// ---------------------------------------------------------------------
enum DatePreset { all, today, yesterday, last7Days, last30Days, thisMonth, custom }

extension DatePresetX on DatePreset {
  String get label => switch (this) {
    DatePreset.all => 'Mọi lúc',
    DatePreset.today => 'Hôm nay',
    DatePreset.yesterday => 'Hôm qua',
    DatePreset.last7Days => '7 ngày qua',
    DatePreset.last30Days => '30 ngày qua',
    DatePreset.thisMonth => 'Tháng này',
    DatePreset.custom => 'Chọn khoảng ngày',
  };
}

enum ReadFilter { all, unread, read }

extension ReadFilterX on ReadFilter {
  String get label => switch (this) {
    ReadFilter.all => 'Tất cả',
    ReadFilter.unread => 'Chưa đọc',
    ReadFilter.read => 'Đã đọc',
  };
}

enum NotificationSort { newest, oldest, unreadFirst }

extension NotificationSortX on NotificationSort {
  String get label => switch (this) {
    NotificationSort.newest => 'Mới nhất',
    NotificationSort.oldest => 'Cũ nhất',
    NotificationSort.unreadFirst => 'Chưa đọc trước',
  };
}

/// Các loại thông báo (khớp NotificationHistory.type).
const Map<String, String> kNotificationTypes = {
  'CLASS': 'Thông báo',
  'BROADCAST': 'Thông báo',
  'ANNOUNCEMENT': 'Thông báo',
  'EXAM': 'Lịch thi',
  'EXAM_ADVANCE': 'Nhắc thi',
  'REMINDER': 'Nhắc nhở',
  'ATTENDANCE_IN': 'Nhắc nhở',
  'ATTENDANCE_OUT': 'Nhắc nhở',
};

const Set<String> _kExamTypes = {'EXAM', 'EXAM_ADVANCE'};

// ---------------------------------------------------------------------
// BỎ DẤU TIẾNG VIỆT (tìm "giai phau" vẫn ra "Giải phẫu")
// ---------------------------------------------------------------------
final Map<int, String> _foldMap = () {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  final m = <int, String>{};
  groups.forEach((base, chars) {
    for (final r in chars.runes) {
      m[r] = base;
    }
  });
  return m;
}();

String foldVietnamese(String input) {
  final sb = StringBuffer();
  for (final r in input.toLowerCase().runes) {
    sb.write(_foldMap[r] ?? String.fromCharCode(r));
  }
  return sb.toString();
}

// ---------------------------------------------------------------------
// NHẬN DIỆN MÔN HỌC
// ---------------------------------------------------------------------
class _SubjectBox {
  final String? value;
  const _SubjectBox(this.value);
}

/// Thông báo hiện KHÔNG có trường "môn" riêng, nên môn được suy ra từ nội dung
/// (vd "Môn: Giải phẫu", "môn Giải phẫu lúc 7h"). Đây là heuristic: nếu server
/// có trả `subject`/`tenMon`... thì giá trị đó luôn được ưu tiên.
/// Có thể thay bằng logic riêng: SubjectExtractor.resolver = (n) => ...;
class SubjectExtractor {
  const SubjectExtractor._();

  static const String noSubjectKey = '__none__';

  static String? Function(FilterableNotification) resolver = extract;

  static final Expando<_SubjectBox> _cache = Expando<_SubjectBox>('subject');

  /// Môn của thông báo (có cache theo từng object).
  static String? of(FilterableNotification n) {
    final hit = _cache[n];
    if (hit != null) return hit.value;
    final v = resolver(n);
    _cache[n] = _SubjectBox(v);
    return v;
  }

  /// Khóa gom nhóm: không phân biệt hoa/thường, dấu, khoảng trắng.
  static String keyOf(String subject) =>
      foldVietnamese(subject).replaceAll(RegExp(r'\s+'), ' ').trim();

  static final List<RegExp> _patterns = [
    // "Môn: Giải phẫu", "Môn học: ...", "Học phần: ..."
    RegExp(r'(?:môn\s*học|học\s*phần|môn)\s*[:：]\s*([^\n\r,;|()\[\]]+)',
        caseSensitive: false),
    // "môn Giải phẫu lúc 7h"
    RegExp(r'(?:môn\s*học|học\s*phần|môn)\s+([^\n\r,;:|()\[\]]+)',
        caseSensitive: false),
  ];

  static const List<String> _stopWords = [
    'lúc', 'vào', 'tại', 'ngày', 'phòng', 'lớp', 'tiết', 'giờ', 'bắt đầu',
    'sẽ', 'đã', 'được', 'bị', 'còn', 'cách', 'sau', 'trước', 'có', 'của',
    'cho', 'thay đổi', 'chuyển', 'hoãn', 'nghỉ',
  ];

  static final RegExp _tail = RegExp(
    '\\s+(?:${_stopWords.join('|')})(?=\\s|\$).*\$',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _reject = RegExp(
    r'^(?:mới|này|nào|đó|của|bạn|sẽ|đã|vào|tại|lúc)(?=\s|$)',
    caseSensitive: false,
  );

  static String? _clean(String raw) {
    var s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.split(RegExp(r'\s[-–—]\s')).first; // cắt tại " - "
    s = s.replaceFirst(_tail, '');
    s = s
        .replaceAll(RegExp(r'''^[\s"'“”‘’:.\-]+|[\s"'“”‘’:.!?\-]+$'''), '')
        .trim();
    if (s.length < 3 || s.length > 60) return null;
    if (_reject.hasMatch(s)) return null;
    return s;
  }

  static String? extract(FilterableNotification n) {
    final explicit = n.subject?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    for (final text in [n.title, n.body]) {
      for (final p in _patterns) {
        final m = p.firstMatch(text);
        if (m == null) continue;
        final cleaned = _clean(m.group(1) ?? '');
        if (cleaned != null) return cleaned;
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------
// FACET MÔN HỌC + NHÓM THEO NGÀY
// ---------------------------------------------------------------------
class SubjectFacet {
  final String key;
  final String label;
  final int count;
  final int unread;
  const SubjectFacet({
    required this.key,
    required this.label,
    required this.count,
    required this.unread,
  });
}

class _FacetAcc {
  final String label;
  int count = 0;
  int unread = 0;
  _FacetAcc(this.label);
}

class NotificationDayHeader {
  final DateTime day; // 00:00 của ngày
  final int count;
  const NotificationDayHeader(this.day, this.count);

  String label([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final diff = today.difference(day).inDays;
    final dm = DateFormat('dd/MM').format(day);
    if (diff == 0) return 'Hôm nay · $dm';
    if (diff == 1) return 'Hôm qua · $dm';
    const names = [
      'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy', 'Chủ nhật',
    ];
    final wd = names[day.weekday - 1];
    return day.year == n.year
        ? '$wd · $dm'
        : '$wd · ${DateFormat('dd/MM/yyyy').format(day)}';
  }
}

// ---------------------------------------------------------------------
// BỘ LỌC (bất biến)
// ---------------------------------------------------------------------
class NotificationFilter {
  static const Object _unset = Object();

  final String query;
  final DatePreset datePreset;
  final DateTimeRange? customRange;
  final Set<String> subjects; // SubjectExtractor.keyOf(...) hoặc noSubjectKey
  final Set<String> types; // 'CLASS', 'EXAM', ...
  final ReadFilter read;
  final NotificationSort sort;
  final bool groupByDay;

  const NotificationFilter({
    this.query = '',
    this.datePreset = DatePreset.all,
    this.customRange,
    this.subjects = const {},
    this.types = const {},
    this.read = ReadFilter.all,
    this.sort = NotificationSort.newest,
    this.groupByDay = true,
  });

  NotificationFilter copyWith({
    String? query,
    DatePreset? datePreset,
    Object? customRange = _unset, // truyền null để xóa
    Set<String>? subjects,
    Set<String>? types,
    ReadFilter? read,
    NotificationSort? sort,
    bool? groupByDay,
  }) {
    return NotificationFilter(
      query: query ?? this.query,
      datePreset: datePreset ?? this.datePreset,
      customRange: identical(customRange, _unset)
          ? this.customRange
          : customRange as DateTimeRange?,
      subjects: subjects ?? this.subjects,
      types: types ?? this.types,
      read: read ?? this.read,
      sort: sort ?? this.sort,
      groupByDay: groupByDay ?? this.groupByDay,
    );
  }

  /// Có điều kiện LỌC nào đang bật (không tính sắp xếp).
  bool get hasCriteria =>
      query.trim().isNotEmpty ||
          datePreset != DatePreset.all ||
          subjects.isNotEmpty ||
          types.isNotEmpty ||
          read != ReadFilter.all;

  /// Số mục đang bật (hiện trên nút "Bộ lọc").
  int get activeCount =>
      (query.trim().isNotEmpty ? 1 : 0) +
          (datePreset != DatePreset.all ? 1 : 0) +
          (subjects.isNotEmpty ? 1 : 0) +
          (types.isNotEmpty ? 1 : 0) +
          (read != ReadFilter.all ? 1 : 0) +
          (sort != NotificationSort.newest ? 1 : 0);

  bool get isActive => activeCount > 0;

  /// Nhóm theo ngày chỉ có nghĩa khi danh sách xếp theo thời gian.
  bool get effectiveGroupByDay =>
      groupByDay && sort != NotificationSort.unreadFirst;

  String get dateLabel {
    final r = customRange;
    if (datePreset == DatePreset.custom && r != null) {
      final full = DateFormat('dd/MM/yyyy');
      if (r.start == r.end) return full.format(r.start);
      return '${DateFormat('dd/MM').format(r.start)} – ${full.format(r.end)}';
    }
    return datePreset.label;
  }

  // ---- Khoảng thời gian [start, end) ----
  (DateTime, DateTime)? _bounds(DateTime now) {
    final y = now.year, m = now.month, d = now.day;
    final today = DateTime(y, m, d);
    final tomorrow = DateTime(y, m, d + 1);
    return switch (datePreset) {
      DatePreset.all => null,
      DatePreset.today => (today, tomorrow),
      DatePreset.yesterday => (DateTime(y, m, d - 1), today),
      DatePreset.last7Days => (DateTime(y, m, d - 6), tomorrow),
      DatePreset.last30Days => (DateTime(y, m, d - 29), tomorrow),
      DatePreset.thisMonth => (DateTime(y, m, 1), DateTime(y, m + 1, 1)),
      DatePreset.custom => customRange == null
          ? null
          : (
      DateTime(customRange!.start.year, customRange!.start.month,
          customRange!.start.day),
      DateTime(customRange!.end.year, customRange!.end.month,
          customRange!.end.day + 1),
      ),
    };
  }

  bool _matches(
      FilterableNotification n,
      (DateTime, DateTime)? bounds,
      String foldedQuery,
      ) {
    if (bounds != null) {
      final t = n.timestamp;
      if (t.isBefore(bounds.$1) || !t.isBefore(bounds.$2)) return false;
    }

    switch (read) {
      case ReadFilter.unread:
        if (n.is_read) return false;
      case ReadFilter.read:
        if (!n.is_read) return false;
      case ReadFilter.all:
        break;
    }

    if (types.isNotEmpty && !types.contains(n.type)) return false;

    if (subjects.isNotEmpty) {
      final s = SubjectExtractor.of(n);
      final key = s == null ? SubjectExtractor.noSubjectKey : SubjectExtractor.keyOf(s);
      if (!subjects.contains(key)) return false;
    }

    if (foldedQuery.isNotEmpty) {
      final hay = foldVietnamese(
          '${n.title}\n${n.body}\n${SubjectExtractor.of(n) ?? ''}');
      if (!hay.contains(foldedQuery)) return false;
    }
    return true;
  }

  /// Lọc + sắp xếp (ổn định). KHÔNG sửa danh sách gốc.
  List<T> apply<T extends FilterableNotification>(
      Iterable<T> source, {
        DateTime? now,
      }) {
    final bounds = _bounds(now ?? DateTime.now());
    final q = foldVietnamese(query).trim();
    final result = <T>[
      for (final n in source)
        if (_matches(n, bounds, q)) n,
    ];
    _sortInPlace(result);
    return result;
  }

  void _sortInPlace<T extends FilterableNotification>(List<T> list) {
    int newest(T a, T b) => b.timestamp.compareTo(a.timestamp);

    int Function(T, T) cmp;
    switch (sort) {
      case NotificationSort.newest:
        cmp = newest;
      case NotificationSort.oldest:
        cmp = (T a, T b) => a.timestamp.compareTo(b.timestamp);
      case NotificationSort.unreadFirst:
        cmp = (T a, T b) {
          if (a.is_read != b.is_read) return a.is_read ? 1 : -1;
          return newest(a, b);
        };
    }

    // List.sort không ổn định → kèm chỉ số gốc để giữ thứ tự khi bằng nhau
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((x, y) {
      final c = cmp(x.$2, y.$2);
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    for (var i = 0; i < list.length; i++) {
      list[i] = indexed[i].$2;
    }
  }

  // ---- Gợi ý: danh sách môn kèm số lượng ----
  static List<SubjectFacet> subjectFacets(Iterable<FilterableNotification> items) {
    final map = <String, _FacetAcc>{};
    for (final n in items) {
      final s = SubjectExtractor.of(n);
      final key = s == null ? SubjectExtractor.noSubjectKey : SubjectExtractor.keyOf(s);
      final acc = map.putIfAbsent(key, () => _FacetAcc(s ?? 'Không rõ môn'));
      acc.count++;
      if (!n.is_read) acc.unread++;
    }
    final list = [
      for (final e in map.entries)
        SubjectFacet(
          key: e.key,
          label: e.value.label,
          count: e.value.count,
          unread: e.value.unread,
        ),
    ];
    list.sort((a, b) {
      if (a.key == SubjectExtractor.noSubjectKey) return 1;
      if (b.key == SubjectExtractor.noSubjectKey) return -1;
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
    return list;
  }

  /// Chèn tiêu đề ngày vào danh sách đã sắp xếp theo thời gian.
  /// Kết quả gồm NotificationDayHeader xen kẽ với phần tử T.
  static List<Object> buildEntries<T extends FilterableNotification>(List<T> items) {
    final out = <Object>[];
    DateTime? current;
    var headerIndex = -1;
    var count = 0;

    for (final n in items) {
      final d = DateTime(n.timestamp.year, n.timestamp.month, n.timestamp.day);
      if (current == null || d != current) {
        if (headerIndex >= 0) {
          out[headerIndex] = NotificationDayHeader(current!, count);
        }
        current = d;
        count = 0;
        headerIndex = out.length;
        out.add(NotificationDayHeader(d, 0));
      }
      out.add(n);
      count++;
    }
    if (headerIndex >= 0) {
      out[headerIndex] = NotificationDayHeader(current!, count);
    }
    return out;
  }
}

// ---------------------------------------------------------------------
// LỌC NHANH (chip có số lượng)
// ---------------------------------------------------------------------
enum QuickFilter { unread, today, last7Days, exams }

extension QuickFilterX on QuickFilter {
  String get label => switch (this) {
    QuickFilter.unread => 'Chưa đọc',
    QuickFilter.today => 'Hôm nay',
    QuickFilter.last7Days => '7 ngày',
    QuickFilter.exams => 'Lịch thi',
  };

  IconData get icon => switch (this) {
    QuickFilter.unread => Icons.mark_email_unread_rounded,
    QuickFilter.today => Icons.today_rounded,
    QuickFilter.last7Days => Icons.date_range_rounded,
    QuickFilter.exams => Icons.assignment_rounded,
  };

  bool isOn(NotificationFilter f) => switch (this) {
    QuickFilter.unread => f.read == ReadFilter.unread,
    QuickFilter.today => f.datePreset == DatePreset.today,
    QuickFilter.last7Days => f.datePreset == DatePreset.last7Days,
    QuickFilter.exams => f.types.length == _kExamTypes.length &&
        f.types.containsAll(_kExamTypes),
  };

  NotificationFilter toggle(NotificationFilter f) {
    final on = isOn(f);
    return switch (this) {
      QuickFilter.unread =>
          f.copyWith(read: on ? ReadFilter.all : ReadFilter.unread),
      QuickFilter.today => f.copyWith(
        datePreset: on ? DatePreset.all : DatePreset.today,
        customRange: null,
      ),
      QuickFilter.last7Days => f.copyWith(
        datePreset: on ? DatePreset.all : DatePreset.last7Days,
        customRange: null,
      ),
      QuickFilter.exams => f.copyWith(types: on ? <String>{} : {..._kExamTypes}),
    };
  }
}

// =====================================================================
// UI: TIÊU ĐỀ NGÀY
// =====================================================================
class NotificationDayHeaderTile extends StatelessWidget {
  final NotificationDayHeader header;
  const NotificationDayHeaderTile({super.key, required this.header});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Text(
            header.label(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${header.count}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// UI: THANH LỌC (đặt dưới TabBar)
// =====================================================================
class NotificationFilterBar extends StatefulWidget {
  final NotificationFilter filter;

  /// Thông báo của tab hiện tại (chưa lọc) → tính số lượng trên chip.
  final List<FilterableNotification> items;
  final ValueChanged<NotificationFilter> onChanged;
  final VoidCallback onOpenSheet;

  const NotificationFilterBar({
    super.key,
    required this.filter,
    required this.items,
    required this.onChanged,
    required this.onOpenSheet,
  });

  @override
  State<NotificationFilterBar> createState() => _NotificationFilterBarState();
}

class _NotificationFilterBarState extends State<NotificationFilterBar> {
  late final TextEditingController _ctrl =
  TextEditingController(text: widget.filter.query);
  Timer? _debounce;
  bool _searching = false;

  @override
  void didUpdateWidget(covariant NotificationFilterBar old) {
    super.didUpdateWidget(old);
    if (widget.filter.query != old.filter.query &&
        widget.filter.query != _ctrl.text) {
      _ctrl.text = widget.filter.query; // đồng bộ khi bộ lọc bị đặt lại từ nơi khác
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) widget.onChanged(widget.filter.copyWith(query: v));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _searching ? _buildSearch(scheme) : _buildChips(scheme),
      ),
    );
  }

  Widget _buildSearch(ColorScheme scheme) {
    return SizedBox(
      key: const ValueKey('search'),
      height: 44,
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onQueryChanged,
        onSubmitted: (v) {
          _debounce?.cancel();
          widget.onChanged(widget.filter.copyWith(query: v));
          setState(() => _searching = false);
        },
        decoration: InputDecoration(
          hintText: 'Tìm theo nội dung, môn học...',
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Xóa & đóng',
            onPressed: () {
              _debounce?.cancel();
              _ctrl.clear();
              setState(() => _searching = false);
              widget.onChanged(widget.filter.copyWith(query: ''));
            },
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildChips(ColorScheme scheme) {
    final f = widget.filter;
    final subjectLabels = {
      for (final s in NotificationFilter.subjectFacets(widget.items)) s.key: s.label,
    };

    final chips = <Widget>[
      // Nút mở bộ lọc đầy đủ
      ActionChip(
        avatar: Icon(Icons.tune_rounded, size: 18, color: scheme.primary),
        label: Text(f.activeCount > 0 ? 'Bộ lọc · ${f.activeCount}' : 'Bộ lọc'),
        backgroundColor: f.activeCount > 0 ? scheme.primaryContainer : null,
        onPressed: widget.onOpenSheet,
      ),
      ActionChip(
        avatar: const Icon(Icons.search_rounded, size: 18),
        label: const Text('Tìm kiếm'),
        onPressed: () => setState(() => _searching = true),
      ),

      // Lọc nhanh + số lượng nếu bấm vào
      for (final q in QuickFilter.values) _quickChip(q, f),

      // Các điều kiện đang bật (xóa từng cái)
      if (f.query.trim().isNotEmpty)
        _activeChip('"${f.query.trim()}"', () {
          _ctrl.clear();
          widget.onChanged(f.copyWith(query: ''));
        }),
      if (f.datePreset != DatePreset.all &&
          f.datePreset != DatePreset.today &&
          f.datePreset != DatePreset.last7Days)
        _activeChip(f.dateLabel,
                () => widget.onChanged(f.copyWith(datePreset: DatePreset.all, customRange: null))),
      for (final key in f.subjects)
        _activeChip(
          subjectLabels[key] ??
              (key == SubjectExtractor.noSubjectKey ? 'Không rõ môn' : key),
              () => widget.onChanged(f.copyWith(subjects: {...f.subjects}..remove(key))),
        ),
      if (f.types.isNotEmpty && !QuickFilter.exams.isOn(f))
        _activeChip(
          f.types.map((t) => kNotificationTypes[t] ?? t).join(', '),
              () => widget.onChanged(f.copyWith(types: <String>{})),
        ),
      if (f.read == ReadFilter.read)
        _activeChip('Đã đọc', () => widget.onChanged(f.copyWith(read: ReadFilter.all))),
      if (f.sort != NotificationSort.newest)
        _activeChip('Xếp: ${f.sort.label}',
                () => widget.onChanged(f.copyWith(sort: NotificationSort.newest))),

      if (f.isActive)
        ActionChip(
          avatar: Icon(Icons.filter_alt_off_rounded, size: 18, color: scheme.error),
          label: Text('Xóa lọc', style: TextStyle(color: scheme.error)),
          onPressed: () {
            _ctrl.clear();
            widget.onChanged(const NotificationFilter());
          },
        ),
    ];

    return SizedBox(
      key: const ValueKey('chips'),
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }

  Widget _quickChip(QuickFilter q, NotificationFilter f) {
    final on = q.isOn(f);
    // Số kết quả nếu người dùng bấm chip này (kết hợp với các bộ lọc khác)
    final count = (on ? f : q.toggle(f)).apply(widget.items).length;
    final enabled = on || count > 0;
    return FilterChip(
      avatar: Icon(q.icon, size: 16),
      label: Text('${q.label} ($count)'),
      selected: on,
      showCheckmark: false,
      onSelected: enabled ? (_) => widget.onChanged(q.toggle(f)) : null,
    );
  }

  Widget _activeChip(String label, VoidCallback onDelete) {
    return InputChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      onDeleted: onDelete,
      visualDensity: VisualDensity.compact,
    );
  }
}

// =====================================================================
// UI: BOTTOM SHEET LỌC ĐẦY ĐỦ
// =====================================================================
Future<NotificationFilter?> showNotificationFilterSheet(
    BuildContext context, {
      required NotificationFilter current,
      required List<SubjectFacet> facets,
      
    }) {
  return showModalBottomSheet<NotificationFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _FilterSheet(
      current: current,
      facets: facets,
      
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  final NotificationFilter current;
  final List<SubjectFacet> facets;
  

  const _FilterSheet({
    required this.current,
    required this.facets,
    
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const int _subjectLimit = 8;

  late NotificationFilter _draft = widget.current;
  bool _showAllSubjects = false;

  void _set(NotificationFilter f) => setState(() => _draft = f);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: last,
      initialDateRange: _draft.customRange,
      helpText: 'Chọn khoảng ngày',
      saveText: 'Áp dụng',
    );
    if (picked != null && mounted) {
      _set(_draft.copyWith(datePreset: DatePreset.custom, customRange: picked));
    }
  }

  Widget _section(String title, Widget child, {String? hint}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.85;
    

    final subjectFacets = widget.facets;
    final hasRealSubjects =
    subjectFacets.any((s) => s.key != SubjectExtractor.noSubjectKey);
    final visibleSubjects = _showAllSubjects
        ? subjectFacets
        : subjectFacets.take(_subjectLimit).toList();

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Bộ lọc thông báo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  onPressed: _draft.isActive
                      ? () => _set(const NotificationFilter())
                      : null,
                  child: const Text('Đặt lại'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              children: [
                // ---- Thời gian ----
                _section(
                  'Thời gian',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in DatePreset.values.where((p) => p != DatePreset.custom))
                        ChoiceChip(
                          label: Text(p.label),
                          selected: _draft.datePreset == p,
                          onSelected: (_) =>
                              _set(_draft.copyWith(datePreset: p, customRange: null)),
                        ),
                      ChoiceChip(
                        avatar: const Icon(Icons.date_range_rounded, size: 18),
                        label: Text(_draft.datePreset == DatePreset.custom
                            ? _draft.dateLabel
                            : 'Chọn khoảng ngày…'),
                        selected: _draft.datePreset == DatePreset.custom,
                        onSelected: (_) => _pickRange(),
                      ),
                    ],
                  ),
                ),

                // ---- Môn học ----
                _section(
                  'Môn học',
                  hasRealSubjects
                      ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in visibleSubjects)
                            FilterChip(
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  '${s.label} (${s.count})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              selected: _draft.subjects.contains(s.key),
                              onSelected: (on) {
                                final next = {..._draft.subjects};
                                on ? next.add(s.key) : next.remove(s.key);
                                _set(_draft.copyWith(subjects: next));
                              },
                            ),
                        ],
                      ),
                      if (subjectFacets.length > _subjectLimit)
                        TextButton(
                          onPressed: () =>
                              setState(() => _showAllSubjects = !_showAllSubjects),
                          child: Text(_showAllSubjects
                              ? 'Thu gọn'
                              : 'Xem thêm ${subjectFacets.length - _subjectLimit} môn'),
                        ),
                    ],
                  )
                      : Text(
                    'Chưa nhận diện được môn học trong các thông báo đã tải.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  hint: 'Nhận diện từ nội dung thông báo, chỉ gồm các thông báo đã tải.',
                ),

                // ---- Loại ----
                _section(
                  'Loại thông báo',
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in kNotificationTypes.entries)
                        FilterChip(
                          label: Text(e.value),
                          selected: _draft.types.contains(e.key),
                          onSelected: (on) {
                            final next = {..._draft.types};
                            on ? next.add(e.key) : next.remove(e.key);
                            _set(_draft.copyWith(types: next));
                          },
                        ),
                    ],
                  ),
                ),

                // ---- Trạng thái ----
                _section(
                  'Trạng thái',
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ReadFilter>(
                      showSelectedIcon: false,
                      segments: [
                        for (final r in ReadFilter.values)
                          ButtonSegment(value: r, label: Text(r.label)),
                      ],
                      selected: {_draft.read},
                      onSelectionChanged: (s) => _set(_draft.copyWith(read: s.first)),
                    ),
                  ),
                ),

                // ---- Sắp xếp + nhóm ----
                _section(
                  'Sắp xếp',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in NotificationSort.values)
                            ChoiceChip(
                              label: Text(s.label),
                              selected: _draft.sort == s,
                              onSelected: (_) => _set(_draft.copyWith(sort: s)),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Nhóm theo ngày'),
                        subtitle: _draft.sort == NotificationSort.unreadFirst
                            ? const Text('Không áp dụng khi xếp "Chưa đọc trước"')
                            : null,
                        value: _draft.groupByDay,
                        onChanged: (v) => _set(_draft.copyWith(groupByDay: v)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _draft),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Xem thông báo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
