import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shimmer/shimmer.dart';

import '../../auth/services/auth_service.dart';
import '../services/attendance_history_service.dart';

/// Parse timestamp từ server, GIỮ NGUYÊN giờ như server trả về,
/// không convert theo timezone thiết bị (vì server đã trả sẵn giờ VN
/// nhưng gắn nhầm hậu tố 'Z').
DateTime _parseServerDateTime(dynamic raw) {
  if (raw == null) return DateTime(1900);
  final str = raw.toString().trim();
  if (str.isEmpty) return DateTime(1900);

  // Server luôn trả giờ VN thật, dù có gắn nhãn Z hay không.
  // KHÔNG được .toLocal() vì sẽ cộng nhầm offset múi giờ.
  final cleaned = str.replaceAll('Z', '').replaceAll('z', '');

  try {
    return DateTime.parse(cleaned);
  } catch (e) {
    debugPrint('❌ Parse date lỗi: "$str" -> $e');
    return DateTime(1900);
  }
}

/// Server dùng mốc 01/01/1900 (bản cũ: năm 1899) để đánh dấu "chưa điểm danh ra".
/// Mọi chỗ hiển thị giờ ra đều dùng chung hàm này để nhất quán.
bool _laThoiGianRong(DateTime dt) => dt.year <= 1900;

/// Phân loại hình thức điểm danh từ giá trị ảnh server trả về.
/// Dùng chung cho cả điểm danh vào/ra, cả card gọn lẫn bottom sheet chi tiết.
String _loaiDiemDanh(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return 'Vân tay';
  if (s.contains('CAMAI')) return 'Khuôn mặt';
  return 'MSSV';
}

/// Chuẩn hóa URL ảnh: server có thể trả 'N/A' hoặc chuỗi rỗng khi không có ảnh.
String? _chuanHoaAnh(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty || s == 'N/A') return null;
  return s;
}

class AttendanceHistoryScreen extends StatefulWidget {
  final Function(int)? onTabSelected;
  const AttendanceHistoryScreen({super.key, this.onTabSelected});

  @override
  AttendanceHistoryScreenState createState() => AttendanceHistoryScreenState();
}

class AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  List<dynamic> _attendanceList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;
  bool _dangTai = false;
  String? _error;

  // Filter states
  String? _selectedMaMon;
  DateTimeRange? _selectedDateRange;
  DateTime? _selectedSingleDate;
  String _dateFilterType = 'none'; // 'none', 'days', 'single', 'range'
  int? _soNgay = 14; // Mặc định 14 ngày
  List<String> _availableMaMon = [];
  Map<String, String> _maMonLabels = {}; // maMon -> "maMon - tenMon"

  String? get _tuNgayParam {
    if (_dateFilterType == 'single' && _selectedSingleDate != null) {
      return DateFormat('yyyy-MM-dd').format(_selectedSingleDate!);
    }
    if (_dateFilterType == 'range' && _selectedDateRange != null) {
      return DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
    }
    return null;
  }

  String? get _denNgayParam {
    if (_dateFilterType == 'single' && _selectedSingleDate != null) {
      return DateFormat('yyyy-MM-dd').format(_selectedSingleDate!);
    }
    if (_dateFilterType == 'range' && _selectedDateRange != null) {
      return DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
    }
    return null;
  }

  int? get _soNgayParam {
    if (_dateFilterType == 'single' || _dateFilterType == 'range') {
      return null;
    }
    return _soNgay ?? 14;
  }

  /// API public cho MainScreen: tab được chọn → tải nếu chưa có dữ liệu.
  void loadTab(int tabIndex) {
    if (!mounted) return;
    if (_attendanceList.isNotEmpty) {
      setState(_applyFilters);
      return;
    }
    _fetchAttendanceHistory();
  }

  /// API public: tải lại dữ liệu.
  Future<void> fetchData({bool forceRefresh = false}) =>
      _fetchAttendanceHistory();

  /// API public: chọn tab và tải mới.
  Future<void> loadTabAndFetch(int tabIndex) => _fetchAttendanceHistory();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAttendanceHistory();
    });
  }

  Future<void> _fetchAttendanceHistory() async {
    if (_dangTai || !mounted) return;

    setState(() {
      _dangTai = true;
      _isLoading = true;
      _error = null;
    });

    try {
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null || idSinhVien.isEmpty) {
        throw Exception('Không tìm thấy thông tin sinh viên');
      }

      debugPrint(
          '🔄 Fetching data từ API: TuNgay=$_tuNgayParam, DenNgay=$_denNgayParam, SoNgay=$_soNgayParam');
      final data = await AttendanceHistoryService.getAttendanceHistory(
        idSinhVien,
        tuNgay: _tuNgayParam,
        denNgay: _denNgayParam,
        soNgay: _soNgayParam,
      );

      // Sort NgayTao giảm dần (dùng chung parser, không toLocal)
      data.sort((a, b) {
        final dateA = _parseServerDateTime(a['NgayTao']);
        final dateB = _parseServerDateTime(b['NgayTao']);
        return dateB.compareTo(dateA);
      });

      if (!mounted) return;
      setState(() {
        _attendanceList = data;
        _extractMaMon();
        _applyFilters();
        _isLoading = false;
        _dangTai = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _dangTai = false;
      });
    }
  }

  void _extractMaMon() {
    final maMonSet = <String>{};
    final labels = <String, String>{};

    for (var item in _attendanceList) {
      final maMon = item['mamon'];
      final tenMon = item['tenmon'];
      if (maMon != null && maMon.toString().isNotEmpty) {
        final maMonStr = maMon.toString();
        maMonSet.add(maMonStr);
        final tenMonStr = (tenMon != null && tenMon.toString().isNotEmpty)
            ? tenMon.toString()
            : '';
        labels[maMonStr] =
        tenMonStr.isNotEmpty ? '$maMonStr - $tenMonStr' : maMonStr;
      }
    }

    _availableMaMon = maMonSet.toList()..sort();
    _maMonLabels = labels;
  }

  void _applyFilters() {
    _filteredList = _attendanceList.where((item) {
      if (_selectedMaMon != null) {
        final maMon = item['mamon']?.toString();
        if (maMon != _selectedMaMon) return false;
      }

      if (_dateFilterType == 'single' && _selectedSingleDate != null) {
        try {
          final thoiGianBD = item['THOIGIANBD'];
          if (thoiGianBD != null) {
            final dateTime = _parseServerDateTime(thoiGianBD);
            final dateOnly =
            DateTime(dateTime.year, dateTime.month, dateTime.day);
            final selectedDate = DateTime(_selectedSingleDate!.year,
                _selectedSingleDate!.month, _selectedSingleDate!.day);
            if (dateOnly != selectedDate) return false;
          }
        } catch (e) {
          return false;
        }
      }

      if (_dateFilterType == 'range' && _selectedDateRange != null) {
        try {
          final thoiGianBD = item['THOIGIANBD'];
          if (thoiGianBD != null) {
            final dateTime = _parseServerDateTime(thoiGianBD);
            final dateOnly =
            DateTime(dateTime.year, dateTime.month, dateTime.day);
            final startDate = DateTime(_selectedDateRange!.start.year,
                _selectedDateRange!.start.month, _selectedDateRange!.start.day);
            final endDate = DateTime(_selectedDateRange!.end.year,
                _selectedDateRange!.end.month, _selectedDateRange!.end.day);
            if (dateOnly.isBefore(startDate) || dateOnly.isAfter(endDate)) {
              return false;
            }
          }
        } catch (e) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        selectedMaMon: _selectedMaMon,
        selectedDateRange: _selectedDateRange,
        selectedSingleDate: _selectedSingleDate,
        dateFilterType: _dateFilterType,
        soNgay: _soNgay,
        availableMaMon: _availableMaMon,
        maMonLabels: _maMonLabels,
        onApply: (maMon, dateRange, singleDate, filterType, soNgay) {
          setState(() {
            _selectedMaMon = maMon;
            _selectedDateRange = dateRange;
            _selectedSingleDate = singleDate;
            _dateFilterType = filterType;
            _soNgay = soNgay;
          });
          _fetchAttendanceHistory();
        },
        onReset: () {
          setState(() {
            _selectedMaMon = null;
            _selectedDateRange = null;
            _selectedSingleDate = null;
            _dateFilterType = 'none';
            _soNgay = 14;
          });
          _fetchAttendanceHistory();
        },
      ),
    );
  }

  bool _isIncompleteCheckout(dynamic item) {
    final thoiGianKT = item['THOIGIANKT'];
    if (thoiGianKT == null) return false;
    try {
      return _laThoiGianRong(_parseServerDateTime(thoiGianKT));
    } catch (e) {
      return false;
    }
  }

  Color _getCardColor(BuildContext context, dynamic item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isIncompleteCheckout(item)) {
      return isDark
          ? Colors.amber.shade200.withValues(alpha: 0.2)
          : Colors.amber.shade50;
    }
    return isDark ? Colors.grey.shade800.withValues(alpha: 0.8) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveFilters = _selectedMaMon != null ||
        _dateFilterType == 'single' ||
        _dateFilterType == 'range' ||
        (_soNgay != 14 && _soNgay != null);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Lịch sử điểm danh',
            style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterBottomSheet,
              ),
              if (hasActiveFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAttendanceHistory,
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return _buildTabSkeleton(isDark);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAttendanceHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredList.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return RefreshIndicator(
      onRefresh: _fetchAttendanceHistory,
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _filteredList.length,
        itemBuilder: (context, index) {
          return _FadeSlide(
            index: index,
            child: _buildCompactAttendanceCard(_filteredList[index], isDark),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final hasActiveFilters = _selectedMaMon != null ||
        _dateFilterType == 'single' ||
        _dateFilterType == 'range' ||
        (_soNgay != 14 && _soNgay != null);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            _attendanceList.isEmpty
                ? 'Chưa có lịch sử điểm danh'
                : 'Không tìm thấy kết quả',
            style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54),
          ),
          if (_attendanceList.isNotEmpty || hasActiveFilters) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedMaMon = null;
                  _selectedDateRange = null;
                  _selectedSingleDate = null;
                  _dateFilterType = 'none';
                  _soNgay = 14;
                });
                _fetchAttendanceHistory();
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabSkeleton(bool isDark) {
    final base = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlight = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade800.withOpacity(0.8)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey.shade200,
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        color: Colors.grey.shade300,
                        margin: const EdgeInsets.only(bottom: 8),
                      ),
                      Container(
                        height: 12,
                        width: 120,
                        color: Colors.grey.shade200,
                        margin: const EdgeInsets.only(bottom: 12),
                      ),
                      Row(
                        children: [
                          _buildSkeletonChip(Colors.green),
                          const SizedBox(width: 8),
                          _buildSkeletonChip(Colors.blue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonChip(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, color: Colors.grey.shade300),
          const SizedBox(width: 6),
          Container(width: 40, height: 12, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  Widget _buildCompactAttendanceCard(dynamic item, bool isDark) {
    final theme = Theme.of(context);
    final tenMon = item['tenmon'] ?? 'N/A';
    final maMon = item['mamon'] ?? 'N/A';
    final thoiGianBD = item['THOIGIANBD'];
    final thoiGianKT = item['THOIGIANKT'];
    final isIncomplete = _isIncompleteCheckout(item);

    String timeIn = 'N/A';
    String timeOut = 'N/A';
    String dateStr = '';

    if (thoiGianBD != null) {
      try {
        final dt = _parseServerDateTime(thoiGianBD);
        timeIn = DateFormat('HH:mm').format(dt);
        dateStr = DateFormat('dd/MM/yyyy').format(dt);
      } catch (e) {}
    }

    if (thoiGianKT != null) {
      try {
        final dt = _parseServerDateTime(thoiGianKT);
        // Mốc rỗng (01/01/1900) → chip gọn hiển thị 00:00
        timeOut =
        _laThoiGianRong(dt) ? '00:00' : DateFormat('HH:mm').format(dt);
      } catch (e) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _getCardColor(context, item),
        borderRadius: BorderRadius.circular(12),
        border: isIncomplete
            ? Border.all(color: Colors.amber.shade600, width: 1.5)
            : Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showAttendanceDetail(item),
          borderRadius: BorderRadius.circular(12),
          splashColor: theme.primaryColor.withOpacity(0.15),
          highlightColor: theme.primaryColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tenMon,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            maMon,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    _buildTimeChip(
                      Icons.login,
                      timeIn,
                      Colors.green,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildTimeChip(
                      Icons.logout,
                      timeOut,
                      isIncomplete ? Colors.amber : Colors.blue,
                      isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAttendanceDetail(dynamic item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttendanceDetailSheet(item: item),
    );
  }

  Widget _buildTimeChip(
      IconData icon, String time, MaterialColor color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: isDark ? color.shade300 : color.shade700),
          const SizedBox(width: 4),
          Text(
            time,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? color.shade200 : color.shade700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  final String? selectedMaMon;
  final DateTimeRange? selectedDateRange;
  final DateTime? selectedSingleDate;
  final String dateFilterType;
  final int? soNgay;
  final List<String> availableMaMon;
  final Map<String, String> maMonLabels;
  final Function(String?, DateTimeRange?, DateTime?, String, int?) onApply;
  final VoidCallback onReset;

  const _FilterBottomSheet({
    required this.selectedMaMon,
    required this.selectedDateRange,
    required this.selectedSingleDate,
    required this.dateFilterType,
    required this.soNgay,
    required this.availableMaMon,
    required this.maMonLabels,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  String? _tempMaMon;
  DateTimeRange? _tempDateRange;
  DateTime? _tempSingleDate;
  String _tempDateFilterType = 'none';
  int? _tempSoNgay = 14;

  @override
  void initState() {
    super.initState();
    _tempMaMon = widget.selectedMaMon;
    _tempDateRange = widget.selectedDateRange;
    _tempSingleDate = widget.selectedSingleDate;
    _tempDateFilterType = widget.dateFilterType;
    _tempSoNgay = widget.soNgay ?? 14;
  }

  Future<void> _selectSingleDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDatePicker(
      context: context,
      initialDate: _tempSingleDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            colorScheme: isDark
                ? ColorScheme.dark(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Colors.grey.shade900,
              onSurface: Colors.white,
            )
                : ColorScheme.light(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _tempSingleDate = picked;
        _tempDateFilterType = 'single';
        _tempDateRange = null;
        _tempSoNgay = null;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _tempDateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            colorScheme: isDark
                ? ColorScheme.dark(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Colors.grey.shade900,
              onSurface: Colors.white,
            )
                : ColorScheme.light(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _tempDateRange = picked;
        _tempDateFilterType = 'range';
        _tempSingleDate = null;
        _tempSoNgay = null;
      });
    }
  }

  bool _isSelected(String type, int? days) =>
      _tempDateFilterType == type &&
          (days == null || _tempSoNgay == days);

  BoxDecoration _optionDecoration(bool selected, bool isDark) {
    return BoxDecoration(
      color: selected
          ? const Color(0xFF6366F1).withOpacity(0.1)
          : Colors.transparent,
      border: Border.all(
        color: selected
            ? const Color(0xFF6366F1)
            : (isDark ? Colors.white24 : Colors.grey.shade300),
        width: selected ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bộ lọc',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Subject filter
                  Text(
                    'Môn học',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _tempMaMon,
                        isExpanded: true,
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor:
                        isDark ? Colors.grey.shade800 : Colors.white,
                        hint: Text(
                          'Tất cả môn học',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Tất cả môn học',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          ...widget.availableMaMon.map((maMon) {
                            final label =
                                widget.maMonLabels[maMon] ?? maMon;
                            return DropdownMenuItem<String?>(
                              value: maMon,
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                  isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _tempMaMon = value;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Date filter type selection
                  Text(
                    'Lọc theo thời gian',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Preset options: 14 ngày / 30 ngày
                  Row(
                    children: [
                      Expanded(
                        child: _buildPresetOption(
                          isDark: isDark,
                          label: '14 ngày gần nhất',
                          sublabel: '(Mặc định)',
                          selected: _isSelected('days', 14) ||
                              _isSelected('none', 14),
                          onTap: () => setState(() {
                            _tempSoNgay = 14;
                            _tempDateFilterType = 'days';
                            _tempSingleDate = null;
                            _tempDateRange = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPresetOption(
                          isDark: isDark,
                          label: '30 ngày gần nhất',
                          sublabel: '(Mở rộng)',
                          selected: _isSelected('days', 30),
                          onTap: () => setState(() {
                            _tempSoNgay = 30;
                            _tempDateFilterType = 'days';
                            _tempSingleDate = null;
                            _tempDateRange = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Single date option
                  _buildDateOption(
                    isDark: isDark,
                    icon: Icons.calendar_today,
                    title: 'Chọn một ngày',
                    subtitle: _tempDateFilterType == 'single' &&
                        _tempSingleDate != null
                        ? DateFormat('dd/MM/yyyy').format(_tempSingleDate!)
                        : null,
                    selected: _tempDateFilterType == 'single',
                    onTap: _selectSingleDate,
                    onClear: () => setState(() {
                      _tempSingleDate = null;
                      _tempDateFilterType = 'none';
                      _tempSoNgay = 14;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Date range option
                  _buildDateOption(
                    isDark: isDark,
                    icon: Icons.date_range,
                    title: 'Chọn khoảng thời gian',
                    subtitle: _tempDateFilterType == 'range' &&
                        _tempDateRange != null
                        ? '${DateFormat('dd/MM/yyyy').format(_tempDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_tempDateRange!.end)}'
                        : null,
                    selected: _tempDateFilterType == 'range',
                    onTap: _selectDateRange,
                    onClear: () => setState(() {
                      _tempDateRange = null;
                      _tempDateFilterType = 'none';
                      _tempSoNgay = 14;
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            widget.onReset();
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Đặt lại',
                            style: TextStyle(
                              color:
                              isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onApply(
                                _tempMaMon,
                                _tempDateRange,
                                _tempSingleDate,
                                _tempDateFilterType,
                                _tempSoNgay);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Áp dụng'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetOption({
    required bool isDark,
    required String label,
    required String sublabel,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: _optionDecoration(selected, isDark),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected
                    ? const Color(0xFF6366F1)
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateOption({
    required bool isDark,
    required IconData icon,
    required String title,
    required String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: _optionDecoration(selected, isDark),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF6366F1)
                  : (isDark ? Colors.white60 : Colors.black54),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF6366F1)
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: onClear,
                color: const Color(0xFF6366F1),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceDetailSheet extends StatelessWidget {
  final dynamic item;

  const _AttendanceDetailSheet({required this.item});

  bool _isIncompleteCheckout() {
    final thoiGianKT = item['THOIGIANKT'];
    if (thoiGianKT == null) return false;
    try {
      return _laThoiGianRong(_parseServerDateTime(thoiGianKT));
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIncomplete = _isIncompleteCheckout();
    final attendanceTypeAnhVao = _loaiDiemDanh(item['AnhVao']);
    final attendanceTypeAnhRa = _loaiDiemDanh(item['AnhRa']);

    // Parse data
    final tenMon = item['tenmon'] ?? 'N/A';
    final maMon = item['mamon'] ?? 'N/A';
    final tenNhom = item['tennhom'] ?? 'N/A';
    final soTietPb = item['sotietpb']?.toString() ?? 'N/A';
    final hocKy = item['hocky']?.toString() ?? 'N/A';
    final nienKhoa = item['nienkhoa'] ?? 'N/A';
    final monThucHanh = item['MonThucHanh'] == true ? 'Có' : 'Không';
    final anhVaoUrl = _chuanHoaAnh(item['AnhVao']);
    final anhRaUrl = _chuanHoaAnh(item['AnhRa']);

    String timeInFull = 'N/A';
    String timeOutFull = 'N/A';
    String dateStr = '';

    if (item['THOIGIANBD'] != null) {
      try {
        final dt = _parseServerDateTime(item['THOIGIANBD']);
        timeInFull = DateFormat('HH:mm - dd/MM/yyyy').format(dt);
        dateStr = DateFormat('EEEE, dd/MM/yyyy', 'vi').format(dt);
      } catch (e) {}
    }

    if (item['THOIGIANKT'] != null) {
      try {
        final dt = _parseServerDateTime(item['THOIGIANKT']);
        // Mốc rỗng (01/01/1900) → "Chưa điểm danh ra"
        timeOutFull = _laThoiGianRong(dt)
            ? 'Chưa điểm danh ra'
            : DateFormat('HH:mm - dd/MM/yyyy').format(dt);
      } catch (e) {}
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.white,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),

              // Header
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chi tiết điểm danh',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (isIncomplete)
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.shade700,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade900,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chưa hoàn thành',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.amber.shade100
                                          : Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Bạn chưa điểm danh ra',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Course Info Section
                    _buildSection(
                      isDark: isDark,
                      title: 'Thông tin môn học',
                      icon: Icons.school,
                      children: [
                        _buildInfoRow(isDark, 'Tên môn học', tenMon),
                        _buildInfoRow(isDark, 'Mã môn', maMon),
                        _buildInfoRow(isDark, 'Tên nhóm', tenNhom),
                        _buildInfoRow(isDark, 'Môn thực hành', monThucHanh),
                        _buildInfoRow(isDark, 'Số tiết phân bổ', soTietPb),
                        _buildInfoRow(isDark, 'Học kỳ', hocKy),
                        _buildInfoRow(isDark, 'Niên khóa', nienKhoa),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Attendance Info Section
                    _buildSection(
                      isDark: isDark,
                      title: 'Thông tin điểm danh',
                      icon: Icons.face_retouching_natural,
                      children: [
                        _buildInfoRow(isDark, 'Ngày điểm danh', dateStr),
                        const SizedBox(height: 12),
                        _buildFaceAttendanceCard(
                          context: context,
                          isDark: isDark,
                          title: 'Điểm danh vào',
                          icon: Icons.login_rounded,
                          time: timeInFull,
                          method: attendanceTypeAnhVao,
                          imageUrl: anhVaoUrl,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 12),
                        _buildFaceAttendanceCard(
                          context: context,
                          isDark: isDark,
                          title: 'Điểm danh ra',
                          icon: Icons.logout_rounded,
                          time: timeOutFull,
                          method: attendanceTypeAnhRa,
                          imageUrl: anhRaUrl,
                          color: isIncomplete ? Colors.amber : Colors.blue,
                          isIncomplete: isIncomplete,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFaceAttendanceCard({
    required BuildContext context,
    required bool isDark,
    required String title,
    required IconData icon,
    required String time,
    required String method,
    String? imageUrl,
    required Color color,
    bool isIncomplete = false,
  }) {
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey.shade800.withOpacity(0.5)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isIncomplete
              ? Colors.amber.withOpacity(0.4)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isIncomplete
                        ? Colors.amber.shade700
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.face,
                        size: 13,
                        color: isDark ? Colors.white38 : Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      method,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasImage) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showFullImage(context, imageUrl, title, time),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _buildPlaceholderImage(isDark),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.zoom_in,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!isIncomplete) ...[
            _buildPlaceholderImage(isDark),
          ],
        ],
      ),
    );
  }

  void _showFullImage(
      BuildContext context, String imageUrl, String title, String time) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$title • $time',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 250,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: Colors.white)),
                    );
                  },
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 250,
                    child: Center(
                      child: Icon(Icons.broken_image,
                          color: Colors.white54, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dùng 2 ngón tay để thu phóng ảnh',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(bool isDark) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.no_photography_outlined,
          size: 20, color: isDark ? Colors.white24 : Colors.black26),
    );
  }

  Widget _buildSection({
    required bool isDark,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
        isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.school,
                  size: 20,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
      bool isDark,
      String label,
      String value, {
        Color? valueColor,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? (isDark ? Colors.white : Colors.black87),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mờ dần + trượt lên khi dòng lịch sử xuất hiện
class _FadeSlide extends StatelessWidget {
  final int index;
  final Widget child;
  const _FadeSlide({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index * 60).clamp(0, 400)),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
