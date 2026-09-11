import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../auth/services/auth_service.dart';
import '../services/attendance_history_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final Function(int)? onTabSelected;
  const AttendanceHistoryScreen({super.key, this.onTabSelected});

  @override
  AttendanceHistoryScreenState createState() => AttendanceHistoryScreenState();
}

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
    print('❌ Parse date lỗi: "$str" -> $e');
    return DateTime(1900);
  }
}


class AttendanceHistoryScreenState extends State<AttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {
  // ✅ STATIC CACHE - Giữ cache giữa các lần navigate
  static List<dynamic> _cachedAttendanceList = [];
  static DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  List<dynamic> _attendanceList = [];
  List<dynamic> _filteredList = [];
  bool _isLoading = true;
  String? _error;

  // Filter states
  String? _selectedMaMon;
  DateTimeRange? _selectedDateRange;
  DateTime? _selectedSingleDate;
  String _dateFilterType = 'none';
  List<String> _availableMaMon = [];

  int _currentTabIndex = 0;
  final Map<int, bool> _tabLoading = {0: false, 1: false, 2: false, 3: false};
  final Map<int, bool> _tabLoaded = {0: false, 1: false, 2: false, 3: false};

  late TabController _tabController;
  bool _tabTransitionLoading = false;

  // ✅ PUBLIC METHOD - Kiểm tra cache trước khi fetch
  void loadTab(int tabIndex) {
    if (!mounted) return;

    // ✅ Kiểm tra cache STATIC trước
    if (_isCacheValid() && _cachedAttendanceList.isNotEmpty) {
      print('📦 Sử dụng STATIC cache, không gọi API');
      print('📦 Cache time: $_lastFetchTime');
      print('📦 Cache còn: ${_cacheDuration.inMinutes - DateTime.now().difference(_lastFetchTime!).inMinutes} phút');

      setState(() {
        _currentTabIndex = tabIndex;
        _isLoading = false;
        _tabTransitionLoading = false;
        // Load từ cache
        _attendanceList = List.from(_cachedAttendanceList);
        _extractMaMon();
        _applyFilters();
      });
      return;
    }

    // Nếu cache hết hạn → fetch mới
    print('❌ Cache hết hạn hoặc chưa có, gọi API...');
    setState(() {
      _currentTabIndex = tabIndex;
      _isLoading = true;
      _tabTransitionLoading = true;
    });

    _fetchAttendanceHistory(tabIndex, forceRefresh: false).then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _tabTransitionLoading = false;
        });
      }
    });
  }

  // ✅ Kiểm tra cache còn hiệu lực không (dùng STATIC)
  bool _isCacheValid() {
    if (_lastFetchTime == null) return false;
    final diff = DateTime.now().difference(_lastFetchTime!);
    final isValid = diff < _cacheDuration;
    print('🔍 Cache check: ${isValid ? "Valid" : "Expired"} (${diff.inMinutes}/${_cacheDuration.inMinutes} phút)');
    return isValid;
  }

  // ✅ PUBLIC METHOD - Fetch data với tùy chọn force refresh
  Future<void> fetchData({bool forceRefresh = false}) async {
    await _fetchAttendanceHistory(_currentTabIndex, forceRefresh: forceRefresh);
  }

  // ✅ PUBLIC METHOD - Load tab và fetch (dùng khi gọi từ ngoài)
  Future<void> loadTabAndFetch(int tabIndex) async {
    if (!mounted) return;

    setState(() {
      _currentTabIndex = tabIndex;
      _isLoading = true;
      _tabTransitionLoading = true;
    });

    await _fetchAttendanceHistory(tabIndex, forceRefresh: true);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _tabTransitionLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        loadTab(_tabController.index);
      }
    });

    // Load tab đầu tiên khi màn hình được mở
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadTab(0);
    });
  }

  // ✅ Fetch với cache logic (lưu vào STATIC)
  Future<void> _fetchAttendanceHistory(int tabIndex, {bool forceRefresh = false}) async {
    // Nếu đang loading → không fetch nữa
    if (_tabLoading[tabIndex] == true) return;

    // Nếu không force refresh và cache còn hiệu lực → không fetch
    if (!forceRefresh && _isCacheValid() && _cachedAttendanceList.isNotEmpty) {
      print('📦 Cache còn hiệu lực, load từ STATIC cache');
      setState(() {
        _attendanceList = List.from(_cachedAttendanceList);
        _extractMaMon();
        _applyFilters();
        _isLoading = false;
        _tabLoaded[tabIndex] = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _tabLoading[tabIndex] = true;
    });

    try {
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null || idSinhVien.isEmpty) {
        throw Exception('Không tìm thấy thông tin sinh viên');
      }

      print('🔄 Fetching data từ API...');
      final data = await AttendanceHistoryService.getAttendanceHistory(idSinhVien);

      // Sort NgayTao giảm dần
      data.sort((a, b) {
        final dateA = DateTime.tryParse(a['NgayTao']?.toString() ?? '') ?? DateTime(1900);
        final dateB = DateTime.tryParse(b['NgayTao']?.toString() ?? '') ?? DateTime(1900);
        return dateB.compareTo(dateA);
      });

      setState(() {
        // ✅ Lưu vào STATIC cache
        _cachedAttendanceList = List.from(data);
        _attendanceList = data;

        _extractMaMon();
        _applyFilters();
        _isLoading = false;
        _tabLoading[tabIndex] = false;
        _tabLoaded[tabIndex] = true;

        // ✅ Cập nhật STATIC cache time
        _lastFetchTime = DateTime.now();
        print('✅ Fetch thành công, cache đến: ${_lastFetchTime!.add(_cacheDuration)}');
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _tabLoading[tabIndex] = false;
      });
    }
  }

  // ✅ Extract mã môn (tách riêng để tái sử dụng)
// Thêm field mới cạnh _availableMaMon

  Map<String, String> _maMonLabels = {}; // maMon -> "maMon - tenMon"

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
        labels[maMonStr] = tenMonStr.isNotEmpty ? '$maMonStr - $tenMonStr' : maMonStr;
      }
    }

    _availableMaMon = maMonSet.toList()..sort();
    _maMonLabels = labels;
  }

  // ✅ Refresh - Force fetch mới (reset STATIC cache)
  Future<void> _fetchAttendanceHistory_refresh() async {
    print('🔄 Force refresh - Reset STATIC cache...');

    setState(() {
      _isLoading = true;
      _error = null;
      // ✅ Reset STATIC cache
      _lastFetchTime = null;
      _cachedAttendanceList = [];
      for (var key in _tabLoaded.keys) {
        _tabLoaded[key] = false;
      }
    });

    try {
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null || idSinhVien.isEmpty) {
        throw Exception('Không tìm thấy thông tin sinh viên');
      }

      print('🔄 Fetching fresh data từ API...');
      final data = await AttendanceHistoryService.getAttendanceHistory(idSinhVien);

      data.sort((a, b) {
        final dateA = DateTime.tryParse(a['NgayTao']?.toString() ?? '') ?? DateTime(1900);
        final dateB = DateTime.tryParse(b['NgayTao']?.toString() ?? '') ?? DateTime(1900);
        return dateB.compareTo(dateA);
      });

      setState(() {
        // ✅ Cập nhật STATIC cache
        _cachedAttendanceList = List.from(data);
        _attendanceList = data;

        _extractMaMon();
        _applyFilters();
        _isLoading = false;
        _tabLoaded[_currentTabIndex] = true;

        // ✅ Cập nhật STATIC cache time
        _lastFetchTime = DateTime.now();
        print('✅ Refresh thành công, STATIC cache mới đến: ${_lastFetchTime!.add(_cacheDuration)}');
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
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
            final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
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
            final dateOnly = DateTime(dateTime.year, dateTime.month, dateTime.day);
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
        availableMaMon: _availableMaMon,
        maMonLabels: _maMonLabels,
        onApply: (maMon, dateRange, singleDate, filterType) {
          setState(() {
            _selectedMaMon = maMon;
            _selectedDateRange = dateRange;
            _selectedSingleDate = singleDate;
            _dateFilterType = filterType;
            _applyFilters();
          });
        },
        onReset: () {
          setState(() {
            _selectedMaMon = null;
            _selectedDateRange = null;
            _selectedSingleDate = null;
            _dateFilterType = 'none';
            _applyFilters();
          });
        },
      ),
    );
  }

  String _getAttendanceType(dynamic item) {
    final anhVao = item['AnhVao']?.toString() ?? '';

    // Nếu đều rỗng → Vân tay
    if (anhVao.isEmpty) {
      return 'Vân tay';
    }

    // Nếu có chữ CAMAI → Khuôn mặt
    if (anhVao.contains('CAMAI')) {
      return 'Khuôn mặt';
    }

    // Mặc định
    return 'MSSV';
  }

  String _getAttendanceTypeAnhRa(dynamic item) {
    final anhRa  = item['AnhRa']?.toString() ?? '';

    // Nếu đều rỗng → Vân tay
    if (anhRa .isEmpty) {
      return 'Vân tay';
    }

    // Nếu có chữ CAMAI → Khuôn mặt
    if (anhRa .contains('CAMAI')) {
      return 'Khuôn mặt';
    }

    // Mặc định
    return 'MSSV';
  }


  bool _isIncompleteCheckout(dynamic item) {
    final thoiGianKT = item['THOIGIANKT'];
    if (thoiGianKT == null) return false;
    try {
      final dateTime = _parseServerDateTime(thoiGianKT);
      return dateTime.year == 1900;
    } catch (e) {
      return false;
    }
  }

  Color _getCardColor(BuildContext context, dynamic item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isIncompleteCheckout(item)) {
      return isDark ? Colors.amber.shade200.withValues(alpha:  0.2) : Colors.amber.shade50;
    }
    return isDark ? Colors.grey.shade800.withValues(alpha:  0.8) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveFilters = _selectedMaMon != null ||
        _dateFilterType == 'single' ||
        _dateFilterType == 'range';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Lịch sử điểm danh', style: TextStyle(fontWeight: FontWeight.bold)),
        // backgroundColor: const Color(0xFF6366F1),
        // backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        // foregroundColor: Colors.white,
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
            onPressed: () => _fetchAttendanceHistory_refresh(),
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_tabTransitionLoading) {
      return _buildTabSkeleton(isDark);
    }

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
                onPressed: () => _fetchAttendanceHistory(_currentTabIndex),
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
      return _buildEmptyState(isDark); // Tạo riêng
    }

    if (_filteredList.isEmpty) {
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
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            if (_attendanceList.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedMaMon = null;
                    _selectedDateRange = null;
                    _selectedSingleDate = null;
                    _dateFilterType = 'none';
                    _applyFilters();
                  });
                },
                icon: const Icon(Icons.clear_all),
                label: const Text('Xóa bộ lọc'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchAttendanceHistory(_currentTabIndex),
      color: const Color(0xFF6366F1),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _filteredList.length,
        itemBuilder: (context, index) {
          return _buildCompactAttendanceCard(_filteredList[index], isDark);
        },
      ),
    );
  }


  Widget _buildEmptyState(bool isDark) {
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
            _attendanceList.isEmpty ? 'Chưa có lịch sử điểm danh' : 'Không tìm thấy kết quả',
            style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.black54),
          ),
          if (_attendanceList.isNotEmpty) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedMaMon = null;
                  _selectedDateRange = null;
                  _selectedSingleDate = null;
                  _dateFilterType = 'none';
                  _applyFilters();
                });
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
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6, // Số dòng giả
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800.withOpacity(0.8) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar skeleton
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
                    // Title
                    Container(
                      height: 16,
                      width: double.infinity,
                      color: Colors.grey.shade300,
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                    // Subtitle
                    Container(
                      height: 12,
                      width: 120,
                      color: Colors.grey.shade200,
                      margin: const EdgeInsets.only(bottom: 12),
                    ),

                    // Time chips
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
    final tenMon = item['tenmon'] ?? 'N/A';
    final maMon = item['mamon'] ?? 'N/A';
    final thoiGianBD = item['THOIGIANBD'];
    final thoiGianKT = item['THOIGIANKT'];
    final attendanceType = _getAttendanceType(item);
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
        if (dt.year == 1899) {
          timeOut = '00:00';
        } else {
          timeOut = DateFormat('HH:mm').format(dt.toLocal());
        }
      } catch (e) {}
    }

    void _onTapItem(dynamic item) {
      _showAttendanceDetail(item);
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
          onTap: () => _onTapItem(item),
          borderRadius: BorderRadius.circular(12),
          splashColor: Theme.of(context).primaryColor.withOpacity(0.15),
          highlightColor: Theme.of(context).primaryColor.withOpacity(0.05),
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


  Widget _buildCompactBadge(String type, bool isDark) {
    final isFingerprint = type == 'Vân tay';
    final baseColor = isFingerprint ? Colors.green : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? baseColor.shade900.withOpacity(0.5)
            : baseColor.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type == 'Vân tay'
                ? Icons.fingerprint
                : type == 'Khuôn mặt'
                ? Icons.face
                : Icons.credit_card,
            size: 12,
            color: isDark ? baseColor.shade300 : baseColor.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            type,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? baseColor.shade300 : baseColor.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(IconData icon, String time, MaterialColor color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(isDark ? 0.3 : 0.3),
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
  final List<String> availableMaMon;
  final Map<String, String> maMonLabels;
  final Function(String?, DateTimeRange?, DateTime?, String) onApply;
  final VoidCallback onReset;

  const _FilterBottomSheet({
    required this.selectedMaMon,
    required this.selectedDateRange,
    required this.selectedSingleDate,
    required this.dateFilterType,
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

  @override
  void initState() {
    super.initState();
    _tempMaMon = widget.selectedMaMon;
    _tempDateRange = widget.selectedDateRange;
    _tempSingleDate = widget.selectedSingleDate;
    _tempDateFilterType = widget.dateFilterType;
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
      });
    }
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: isDark ? Colors.grey.shade800 : Colors.white,
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
                            final label = widget.maMonLabels[maMon] ?? maMon;
                            return DropdownMenuItem<String?>(
                              value: maMon,
                              child: Text(
                                label,
                                maxLines: 1,                     // ✅ giới hạn 1 dòng
                                overflow: TextOverflow.ellipsis, // ✅ dài quá thì hiện ...
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
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

                  // Single date option
                  InkWell(
                    onTap: _selectSingleDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _tempDateFilterType == 'single'
                            ? const Color(0xFF6366F1).withOpacity(0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: _tempDateFilterType == 'single'
                              ? const Color(0xFF6366F1)
                              : (isDark ? Colors.white24 : Colors.grey.shade300),
                          width: _tempDateFilterType == 'single' ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: _tempDateFilterType == 'single'
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
                                  'Chọn một ngày',
                                  style: TextStyle(
                                    fontWeight: _tempDateFilterType == 'single'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _tempDateFilterType == 'single'
                                        ? const Color(0xFF6366F1)
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                if (_tempSingleDate != null && _tempDateFilterType == 'single') ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('dd/MM/yyyy').format(_tempSingleDate!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_tempDateFilterType == 'single')
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() {
                                  _tempSingleDate = null;
                                  _tempDateFilterType = 'none';
                                });
                              },
                              color: const Color(0xFF6366F1),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date range option
                  InkWell(
                    onTap: _selectDateRange,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _tempDateFilterType == 'range'
                            ? const Color(0xFF6366F1).withOpacity(0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: _tempDateFilterType == 'range'
                              ? const Color(0xFF6366F1)
                              : (isDark ? Colors.white24 : Colors.grey.shade300),
                          width: _tempDateFilterType == 'range' ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.date_range,
                            color: _tempDateFilterType == 'range'
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
                                  'Chọn khoảng thời gian',
                                  style: TextStyle(
                                    fontWeight: _tempDateFilterType == 'range'
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _tempDateFilterType == 'range'
                                        ? const Color(0xFF6366F1)
                                        : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                if (_tempDateRange != null && _tempDateFilterType == 'range') ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${DateFormat('dd/MM/yyyy').format(_tempDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_tempDateRange!.end)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_tempDateFilterType == 'range')
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() {
                                  _tempDateRange = null;
                                  _tempDateFilterType = 'none';
                                });
                              },
                              color: const Color(0xFF6366F1),
                            ),
                        ],
                      ),
                    ),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: isDark ? Colors.white24 : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Đặt lại',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onApply(_tempMaMon, _tempDateRange, _tempSingleDate, _tempDateFilterType);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
}



class _AttendanceDetailSheet extends StatelessWidget {
  final dynamic item;

  const _AttendanceDetailSheet({required this.item});



  String _getAttendanceTypeChamVao() {
    final anhVao = item['AnhVao']?.toString() ?? '';

    // Nếu đều rỗng → Vân tay
    if (anhVao.isEmpty) {
      return 'Vân tay';
    }

    // Nếu có chữ CAMAI → Khuôn mặt
    if (anhVao.contains('CAMAI')) {
      return 'Khuôn mặt';
    }

    // Mặc định
    return 'MSSV';
  }

  String _getAttendanceTypeChamRa() {
    final anhRa  = item['AnhRa']?.toString() ?? '';

    // Nếu đều rỗng → Vân tay
    if (anhRa.isEmpty) {
      return 'Vân tay';
    }

    // Nếu có chữ CAMAI → Khuôn mặt
    if (anhRa.contains('CAMAI')) {
      return 'Khuôn mặt';
    }

    // Mặc định
    return 'MSSV';
  }

  bool _isIncompleteCheckout() {
    final thoiGianKT = item['THOIGIANKT'];
    if (thoiGianKT == null) return false;
    try {
      final dateTime = _parseServerDateTime(thoiGianKT);
      return dateTime.year == 1900;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isIncomplete = _isIncompleteCheckout();
    final attendanceTypeAnhVao = _getAttendanceTypeChamVao();
    final attendanceTypeAnhRa = _getAttendanceTypeChamRa();
    // Parse data
    final tenMon = item['tenmon'] ?? 'N/A';
    final maMon = item['mamon'] ?? 'N/A';
    final tenNhom = item['tennhom'] ?? 'N/A';
    final hoTen = item['hoten'] ?? 'N/A';
    final maSo = item['maso'] ?? 'N/A';
    final ngaySinh = item['ngaysinh'] ?? 'N/A';
    final tenLop = item['tenlop'] ?? 'N/A';
    final soTietPb = item['sotietpb']?.toString() ?? 'N/A';
    final hocKy = item['hocky']?.toString() ?? 'N/A';
    final nienKhoa = item['nienkhoa'] ?? 'N/A';
    final monThucHanh = item['MonThucHanh'] == true ? 'Có' : 'Không';
    final anhVaoUrl = item['AnhVao']?.toString() ?? 'N/A';
    final anhRaUrl = item['AnhRa']?.toString() ?? 'N/A';

    String timeInFull = 'N/A';
    String timeOutFull = 'N/A';
    String dateStr = '';

    if (item['THOIGIANBD'] != null) {
      print(item['THOIGIANBD'] + "Thoi Gina");
      try {
        final dt = _parseServerDateTime(item['THOIGIANBD']);
        timeInFull = DateFormat('HH:mm - dd/MM/yyyy').format(dt.toLocal());
        dateStr = DateFormat('EEEE, dd/MM/yyyy', 'vi').format(dt.toLocal());
      } catch (e) {}
    }

    if (item['THOIGIANKT'] != null) {
      try {
        final dt = _parseServerDateTime(item['THOIGIANKT']);
        if (dt.year == 1899) {
          timeOutFull = 'Chưa điểm danh ra';
        } else {
          timeOutFull = DateFormat('HH:mm - dd/MM/yyyy').format(dt.toLocal());
        }
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    // Status Card
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chưa hoàn thành',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.amber.shade100 : Colors.amber.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Bạn chưa điểm danh ra',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
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
                      icon: Icons.face_retouching_natural, // Đã đổi từ vân tay sang khuôn mặt
                      children: [
                        _buildInfoRow(isDark, 'Ngày điểm danh', dateStr),

                        const SizedBox(height: 12),

                        // Điểm danh vào
                        _buildFaceAttendanceCard(
                          context: context,
                          isDark: isDark,
                          title: 'Điểm danh vào',
                          icon: Icons.login_rounded,
                          time: timeInFull,
                          method: attendanceTypeAnhVao,
                          imageUrl: anhVaoUrl, // URL ảnh khuôn mặt lúc vào
                          color: Colors.green,
                        ),

                        const SizedBox(height: 12),

                        // Điểm danh ra
                        _buildFaceAttendanceCard(
                          context: context,
                          isDark: isDark,
                          title: 'Điểm danh ra',
                          icon: Icons.logout_rounded,
                          time: timeOutFull,
                          method: attendanceTypeAnhRa,
                          imageUrl: anhRaUrl, // URL ảnh khuôn mặt lúc ra
                          color: isIncomplete ? Colors.amber : Colors.blue,
                          isIncomplete: isIncomplete,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Student Info Section
                    // _buildSection(
                    //   isDark: isDark,
                    //   title: 'Thông tin sinh viên',
                    //   icon: Icons.person,
                    //   children: [
                    //     _buildInfoRow(isDark, 'Họ và tên', hoTen),
                    //     _buildInfoRow(isDark, 'Mã số SV', maSo),
                    //     _buildInfoRow(isDark, 'Ngày sinh', ngaySinh),
                    //     if (tenLop.isNotEmpty && tenLop != 'N/A')
                    //       _buildInfoRow(isDark, 'Lớp', tenLop),
                    //   ],
                    // ),

                    // const SizedBox(height: 20),

                    // Technical Info (Collapsible)
                    // if (item['IDGIOHOC'] != null)
                    //   ExpansionTile(
                    //     tilePadding: EdgeInsets.zero,
                    //     backgroundColor: Colors.transparent,
                    //     collapsedBackgroundColor: Colors.transparent,
                    //     title: Text(
                    //       'Thông tin kỹ thuật',
                    //       style: TextStyle(
                    //         fontSize: 14,
                    //         fontWeight: FontWeight.w600,
                    //         color: isDark ? Colors.white60 : Colors.black54,
                    //       ),
                    //     ),
                    //     children: [
                    //       _buildInfoRow(isDark, 'ID Giờ học', item['IDGIOHOC']?.toString() ?? 'N/A'),
                    //       _buildInfoRow(isDark, 'ID Lịch dạy', item['IDLICHDAY']?.toString() ?? 'N/A'),
                    //       _buildInfoRow(isDark, 'ID Sinh viên', item['IDSV']?.toString() ?? 'N/A'),
                    //       if (item['NgayTao'] != null)
                    //         _buildInfoRow(
                    //           isDark,
                    //           'Ngày tạo',
                    //           DateFormat('HH:mm:ss - dd/MM/yyyy').format(
                    //             _parseServerDateTime(item['NgayTao']).toLocal(),
                    //           ),
                    //         ),
                    //     ],
                    //   ),
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
        color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isIncomplete
              ? Colors.amber.withOpacity(0.4)
              : (isDark ? Colors.white10 : Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          // Icon trạng thái
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

          // Chi tiết text
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
                    color: isIncomplete ? Colors.amber.shade700 : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.face, size: 13, color: isDark ? Colors.white38 : Colors.black38),
                    const SizedBox(width: 4),
                    Text(
                      method.isEmpty ? 'Nhận diện khuôn mặt' : method,
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

          // Thumbnail ảnh khuôn mặt (Bấm vào để xem rõ nét)
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
                      errorBuilder: (_, __, ___) => _buildPlaceholderImage(isDark),
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
                      child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
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

  void _showFullImage(BuildContext context, String imageUrl, String title, String time) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header dialog
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$title • $time',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            // Ảnh có thể zoom/pan
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
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    );
                  },
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.no_photography_outlined, size: 20, color: isDark ? Colors.white24 : Colors.black26),
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
        color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.grey.shade50,
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
                child: Icon(
                  icon,
                  size: 20,
                  color: const Color(0xFF6366F1),
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
        Widget? valueWidget,
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
            child: valueWidget ??
                Text(
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

  Widget _buildMethodBadge(String type, bool isDark) {
    final isFingerprint = type == 'Vân tay';
    final baseColor = isFingerprint ? Colors.green : Colors.blue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? baseColor.shade900.withOpacity(0.5) : baseColor.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFingerprint ? Icons.fingerprint : Icons.credit_card,
            size: 14,
            color: isDark ? baseColor.shade300 : baseColor.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            type,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? baseColor.shade300 : baseColor.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBlock({
    required bool isDark,
    required String title,
    required IconData icon,
    required String time,
    required String method,
    required MaterialColor color,
    bool isIncomplete = false,
  }) {
    final isFingerprint = method ;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.1)
            : color.shade50.withValues(alpha : 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? color.shade700.withValues( alpha: 0.3)
              : color.shade200,
          width: 1.5,
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
                  color: isDark
                      ? color.shade900.withValues(alpha: 0.5)
                      : color.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isDark ? color.shade300 : color.shade700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark
                      ? color.shade900.withValues(alpha: 0.7)
                      : color.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? color.shade700 : color.shade300,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    (time.contains("Chưa điểm danh ra"))
                        ? Text(
                      "Chưa xác định",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black54,

                      ),
                    )
                        : Row(
                      children: [
                        Icon(
                          isFingerprint == 'Vân tay'
                              ? Icons.fingerprint
                              : isFingerprint == 'Khuôn mặt'
                              ? Icons.face
                              : Icons.credit_card,
                          size: 14,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          method,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),


                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: isDark ? color.shade400 : color.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (isIncomplete) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'Chưa hoàn thành',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


