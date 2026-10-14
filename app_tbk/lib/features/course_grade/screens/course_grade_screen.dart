import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/course_grade/models/course_grade.dart';
import 'package:app_tbk/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CourseGradeScreen extends StatefulWidget {
  const CourseGradeScreen({Key? key}) : super(key: key);

  @override
  State<CourseGradeScreen> createState() => _CourseGradeScreenState();
}

class _CourseGradeScreenState extends State<CourseGradeScreen> {
  bool _isLoading = true;
  String? _error;
  List<CourseGrade> _allGrades = [];
  
  // Danh sách học kỳ - niên khóa duy nhất để làm bộ lọc
  List<String> _termList = [];
  String _selectedTerm = 'Tất cả'; // 'Tất cả' hoặc 'Học kỳ X - YYYY-YYYY'

  @override
  void initState() {
    super.initState();
    _fetchCourseGrades();
  }

  Future<void> _fetchCourseGrades() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null) {
        throw Exception('Không tìm thấy ID sinh viên');
      }

      final data = await ApiService.getCourseGrades(int.parse(idSinhVien.toString()));
      final grades = data.map((e) => CourseGrade.fromJson(e)).toList();

      // Tạo danh sách các Học kỳ - Niên khóa
      final Set<String> terms = {};
      for (var grade in grades) {
        terms.add('Học kỳ ${grade.hocKy} - ${grade.nienKhoa}');
      }
      
      // Sắp xếp bộ lọc giảm dần
      final sortedTerms = terms.toList()..sort((a, b) {
        // Parse "Học kỳ X - YYYY-YYYY"
        final partsA = a.split(' - ');
        final partsB = b.split(' - ');
        if (partsA.length == 2 && partsB.length == 2) {
          final yearA = partsA[1];
          final yearB = partsB[1];
          final yearComparison = yearB.compareTo(yearA);
          if (yearComparison != 0) return yearComparison;
          
          final hkA = partsA[0];
          final hkB = partsB[0];
          return hkB.compareTo(hkA);
        }
        return b.compareTo(a);
      });

      setState(() {
        _allGrades = grades;
        _termList = ['Tất cả', ...sortedTerms];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Color _getColorForDiemChu(String diemChu, bool isDark) {
    switch (diemChu) {
      case 'A':
        return isDark ? Colors.blue.shade300 : Colors.blue.shade700;
      case 'B':
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      case 'C':
        return isDark ? Colors.orange.shade300 : Colors.orange.shade700;
      case 'D':
        return isDark ? Colors.amber.shade400 : Colors.amber.shade800;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Điểm học phần',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black87,
        ),
        centerTitle: true,
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return _buildLoadingShimmer(theme, isDark);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchCourseGrades,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allGrades.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Chưa có dữ liệu điểm học phần',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildFilter(theme, isDark),
        Expanded(
          child: _buildGradesList(theme, isDark),
        ),
      ],
    );
  }

  Widget _buildLoadingShimmer(ThemeData theme, bool isDark) {
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return Column(
      children: [
        // Filter Skeleton
        Container(
          width: double.infinity,
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 13, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 4,
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: baseColor,
                highlightColor: highlightColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
                      child: Container(width: 150, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Container(height: 16, margin: const EdgeInsets.only(right: 16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))),
                              Container(width: 40, height: 24, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(height: 1, color: Colors.white),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(children: [Container(width: 50, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))), const SizedBox(height: 4), Container(width: 30, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))]),
                              Column(children: [Container(width: 50, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))), const SizedBox(height: 4), Container(width: 30, height: 16, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))]),
                              Column(children: [Container(width: 60, height: 12, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))), const SizedBox(height: 4), Container(width: 40, height: 18, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)))]),
                              Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
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
        ),
      ],
    );
  }

  Widget _buildFilter(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lọc theo học kỳ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTerm,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                items: _termList.map((term) {
                  return DropdownMenuItem<String>(
                    value: term,
                    child: Text(
                      term,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedTerm = value;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradesList(ThemeData theme, bool isDark) {
    // Lọc theo tùy chọn
    List<CourseGrade> filteredGrades = _allGrades;
    if (_selectedTerm != 'Tất cả') {
      filteredGrades = _allGrades.where((grade) {
        return 'Học kỳ ${grade.hocKy} - ${grade.nienKhoa}' == _selectedTerm;
      }).toList();
    }

    // Nhóm theo Học kỳ - Niên khóa
    final Map<String, List<CourseGrade>> groupedGrades = {};
    for (var grade in filteredGrades) {
      final termKey = 'Học kỳ ${grade.hocKy} - ${grade.nienKhoa}';
      if (!groupedGrades.containsKey(termKey)) {
        groupedGrades[termKey] = [];
      }
      groupedGrades[termKey]!.add(grade);
    }

    // Sắp xếp các term giảm dần
    final sortedTerms = groupedGrades.keys.toList()..sort((a, b) {
      final partsA = a.split(' - ');
      final partsB = b.split(' - ');
      if (partsA.length == 2 && partsB.length == 2) {
        final yearA = partsA[1];
        final yearB = partsB[1];
        final yearComparison = yearB.compareTo(yearA);
        if (yearComparison != 0) return yearComparison;
        
        final hkA = partsA[0];
        final hkB = partsB[0];
        return hkB.compareTo(hkA);
      }
      return b.compareTo(a);
    });

    if (filteredGrades.isEmpty) {
      return Center(
        child: Text(
          'Không có điểm trong học kỳ này',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      );
    }

    // Làm phẳng danh sách để ListView render mượt mà hơn (lazy load)
    final List<dynamic> listItems = [];
    for (var termKey in sortedTerms) {
      listItems.add(termKey);
      listItems.addAll(groupedGrades[termKey]!);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: listItems.length,
      itemBuilder: (context, index) {
        final item = listItems[index];
        
        if (item is String) {
          // Render Header Học kỳ
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
            ),
          );
        } else if (item is CourseGrade) {
          // Render Card Điểm học phần
          return _buildGradeCard(item, isDark, theme);
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildGradeCard(CourseGrade grade, bool isDark, ThemeData theme) {
    final diemChuColor = _getColorForDiemChu(grade.diemChu, isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tên môn học
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    grade.tenMon,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${grade.soTinChi} TC',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            
            // Chi tiết điểm
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildScoreItem('Giữa kỳ', grade.diemGiuaKy.toStringAsFixed(1), isDark),
                _buildScoreItem('Cuối kỳ', grade.diemCuoiKy.toStringAsFixed(1), isDark),
                _buildScoreItem('Tổng kết', grade.diemTongKet.toStringAsFixed(1), isDark, isHighlight: true),
                
                // Điểm chữ badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: diemChuColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      grade.diemChu,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: diemChuColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreItem(String label, String score, bool isDark, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          score,
          style: TextStyle(
            fontSize: isHighlight ? 18 : 16,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
            color: isHighlight
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
          ),
        ),
      ],
    );
  }
}
