import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/subject_attendance.dart';

class AbsenceDetailScreen extends StatelessWidget {
  final SubjectAttendance subject;

  const AbsenceDetailScreen({Key? key, required this.subject}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isBanned = subject.isBanned;
    final color = isBanned ? Colors.red : (subject.isWarning ? Colors.orange : Colors.green);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết vắng học', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            color: color.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.tenMon,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isBanned ? 'Cấm thi' : (subject.isWarning ? 'Chú ý' : 'An toàn'),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Đã vắng ${subject.absentPeriods}/${subject.allowedAbsentPeriods} tiết',
                        style: TextStyle(fontWeight: FontWeight.bold, color: color),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (subject.absentPeriods / (subject.allowedAbsentPeriods > 0 ? subject.allowedAbsentPeriods : 1)).clamp(0.0, 1.0),
                  backgroundColor: Colors.white,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          
          // Danh sách
          Expanded(
            child: subject.absentClasses.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                        SizedBox(height: 16),
                        Text('Chưa vắng buổi nào', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: subject.absentClasses.length,
                    itemBuilder: (context, index) {
                      final lop = subject.absentClasses[index];
                      // lop is actually a LopHoc instance
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.withOpacity(0.1),
                            child: const Icon(Icons.event_busy, color: Colors.red),
                          ),
                          title: Text(
                            DateFormat('EEEE, dd/MM/yyyy').format(lop.ngayBd),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${lop.gioBd} - ${lop.gioKt} • Phòng: ${lop.tenPhong}'),
                                const SizedBox(height: 2),
                                Text('Số tiết: ${lop.soTiet}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
