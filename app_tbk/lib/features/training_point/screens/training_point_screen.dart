import 'package:app_tbk/features/auth/services/auth_service.dart';
import 'package:app_tbk/features/training_point/models/training_point.dart';
import 'package:app_tbk/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class TrainingPointScreen extends StatefulWidget {
  const TrainingPointScreen({Key? key}) : super(key: key);

  @override
  State<TrainingPointScreen> createState() => _TrainingPointScreenState();
}

class _TrainingPointScreenState extends State<TrainingPointScreen> {
  bool _isLoading = true;
  String? _error;
  List<TrainingPoint> _points = [];

  @override
  void initState() {
    super.initState();
    _fetchTrainingPoints();
  }

  Future<void> _fetchTrainingPoints() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final idSinhVien = await AuthService.getIdSinhVien();
      if (idSinhVien == null) {
        throw Exception('Không tìm thấy ID sinh viên');
      }

      final data = await ApiService.getTrainingPoints(int.parse(idSinhVien.toString()));
      final points = data.map((e) => TrainingPoint.fromJson(e)).toList();

      // Sắp xếp theo năm học giảm dần, học kỳ giảm dần
      points.sort((a, b) {
        int yearComparison = b.namHoc.compareTo(a.namHoc);
        if (yearComparison != 0) return yearComparison;
        return b.hocKy.compareTo(a.hocKy);
      });

      setState(() {
        _points = points;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Color _getColorForXepLoai(String xepLoai, bool isDark) {
    switch (xepLoai) {
      case 'Xuất sắc':
        return isDark ? Colors.blue.shade300 : Colors.blue.shade700;
      case 'Tốt':
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      case 'Khá':
        return isDark ? Colors.orange.shade300 : Colors.orange.shade700;
      case 'Trung bình':
        return isDark ? Colors.yellow.shade400 : Colors.yellow.shade800;
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
          'Điểm rèn luyện',
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
                onPressed: _fetchTrainingPoints,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_points.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Chưa có dữ liệu điểm rèn luyện',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _points.length,
      itemBuilder: (context, index) {
        final point = _points[index];
        return _buildPointCard(point, isDark, theme);
      },
    );
  }

  Widget _buildLoadingShimmer(ThemeData theme, bool isDark) {
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: baseColor,
          highlightColor: highlightColor,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 100, height: 18, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                        const SizedBox(height: 8),
                        Container(width: 150, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                      ],
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPointCard(TrainingPoint point, bool isDark, ThemeData theme) {
    final xepLoaiColor = _getColorForXepLoai(point.xepLoai, isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Cột điểm
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: xepLoaiColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  point.diemRl.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: xepLoaiColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Cột thông tin học kỳ/năm học
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Học kỳ ${point.hocKy}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Năm học: ${point.namHoc}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            
            // Xếp loại badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: xepLoaiColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                point.xepLoai,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
