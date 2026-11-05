import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shimmer/shimmer.dart';
import '../models/subject_attendance.dart';
import '../services/absence_warning_service.dart';
import '../screens/absence_detail_screen.dart';

class AbsenceWarningCard extends StatefulWidget {
  const AbsenceWarningCard({Key? key}) : super(key: key);

  @override
  State<AbsenceWarningCard> createState() => _AbsenceWarningCardState();
}

class _AbsenceWarningCardState extends State<AbsenceWarningCard> {
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  List<SubjectAttendance> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool refresh = false}) async {
    if (!mounted) return;
    setState(() {
      if (refresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      _error = null;
    });

    try {
      final results = await AbsenceWarningService.checkAndWarn();
      if (!mounted) return;
      setState(() {
        _subjects = results;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      final hadData = _subjects.isNotEmpty;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        if (!hadData) _error = e.toString();
      });
      // Refresh lỗi nhưng đã có dữ liệu cũ → giữ dữ liệu, báo nhẹ bằng snackbar
      if (hadData && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('absence_warning.load_failed'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton(context);
    if (_error != null) return _buildErrorCard(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final warningSubjects =
    _subjects.where((s) => s.isBanned || s.isWarning || s.absentPeriods > 0).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      elevation: 2,
      // Dark mode: dùng slate-800 để hài hòa với nền navy 0xFF0F172A
      // (đồng bộ với các section ở màn hình Cá nhân)
      color: isDark ? const Color(0xFF1E293B) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      warningSubjects.isEmpty
                          ? Icons.check_circle
                          : Icons.warning_rounded,
                      color: warningSubjects.isEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'absence_warning.title'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                _isRefreshing
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _loadData(refresh: true),
                  tooltip: 'absence_warning.reload'.tr(),
                ),
              ],
            ),
            if (_isRefreshing) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 12),
            if (warningSubjects.isEmpty)
              _buildGoodStatus(context, isDark)
            else
              ...warningSubjects.asMap().entries.map(
                    (e) => _FadeSlide(
                  index: e.key,
                  child: _buildSubjectProgress(context, e.value, isDark),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoodStatus(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'absence_warning.good_status'.tr(),
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectProgress(
      BuildContext context, SubjectAttendance subject, bool isDark) {
    final theme = Theme.of(context);
    final isBanned = subject.isBanned;
    final color = isBanned ? Colors.red : Colors.orange;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AbsenceDetailScreen(subject: subject),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subject.tenMon,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBanned
                        ? 'absence_warning.banned'.tr()
                        : 'absence_warning.warning'.tr(),
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                )
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (subject.absentPeriods /
                    (subject.allowedAbsentPeriods > 0
                        ? subject.allowedAbsentPeriods
                        : 1))
                    .clamp(0.0, 1.0),
                backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'absence_warning.absent_info'.tr(namedArgs: {
                'absentPeriods': subject.absentPeriods.toString(),
                'allowedPeriods': subject.allowedAbsentPeriods.toString()
              }),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'absence_warning.context_info'.tr(namedArgs: {
                'pastSessions': subject.pastSessions.toString(),
                'totalSessions': subject.totalSessions.toString(),
                'totalPeriods': subject.totalPeriods.toString()
              }),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      color: isDark ? const Color(0xFF1E293B) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text('absence_warning.load_failed'.tr()),
            ),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('absence_warning.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    Widget buildSkeletonItem() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 160,
                  height: 16,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 64,
                  height: 20,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 8,
              width: double.infinity,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 13,
              width: 150,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 12,
              width: 230,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Card(
        margin: const EdgeInsets.only(bottom: 24),
        color: isDark ? const Color(0xFF1E293B) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: base,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 160,
                        height: 20,
                        decoration: BoxDecoration(
                          color: base,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: base,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // List item skeletons matching real items
              buildSkeletonItem(),
              const Divider(height: 16, thickness: 0.5),
              buildSkeletonItem(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mờ dần + trượt lên khi dòng môn học xuất hiện
class _FadeSlide extends StatelessWidget {
  final int index;
  final Widget child;
  const _FadeSlide({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index * 80).clamp(0, 400)),
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
