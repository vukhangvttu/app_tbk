// lib/screens/notification_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List thongBaoList = [];
  bool dangTai = true;

  @override
  void initState() {
    super.initState();
    taiThongBao();
  }

  Future<void> taiThongBao() async {
    setState(() => dangTai = true);
    try {
      final url = Uri.parse(
          'http://10.0.2.2:8202/api/thoi-khoa-bieu/thong-bao?idSinhVien=1979');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final duLieu = jsonDecode(response.body);
        setState(() {
          thongBaoList = duLieu;
          dangTai = false;
        });
      } else {
        setState(() => dangTai = false);
      }
    } catch (e) {
      setState(() => dangTai = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Lấy theme từ context để tự động cập nhật
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Thông báo',
          style: TextStyle(
            color: theme.textTheme.titleLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: dangTai
          ? Center(
        child: CircularProgressIndicator(
          color: theme.primaryColor,
        ),
      )
          : thongBaoList.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 80,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có thông báo nào',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: taiThongBao,
        color: theme.primaryColor,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: thongBaoList.length,
          itemBuilder: (context, index) {
            final tb = thongBaoList[index];

            // 🔍 Xác định loại lịch để chọn màu
            final loaiLich = tb['loaiLich'] ?? 'LICH_HOC';
            final mau = loaiLich == 'LICH_THI'
                ? const Color(0xFFF44336) // 🔴 Đỏ - lịch thi
                : const Color(0xFF2196F3); // 🔵 Xanh - lịch học

            final icon = loaiLich == 'LICH_THI'
                ? Icons.event_available
                : Icons.school;

            final ngay = tb['ngayTao'] != null
                ? DateFormat('dd/MM/yyyy HH:mm')
                .format(DateTime.parse(tb['ngayTao']))
                : '';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: theme.cardColor,
              elevation: isDark ? 2 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark
                      ? Colors.grey[800]!
                      : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: mau.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: mau, size: 28),
                ),
                title: Text(
                  tb['tieuDe'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.textTheme.titleMedium?.color,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tb['noiDung'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            ngay,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    );
  }
}