class TrainingPoint {
  final int idsv;
  final int hocKy;
  final String namHoc;
  final int diemRl;

  TrainingPoint({
    required this.idsv,
    required this.hocKy,
    required this.namHoc,
    required this.diemRl,
  });

  factory TrainingPoint.fromJson(Map<String, dynamic> json) {
    return TrainingPoint(
      idsv: json['idsv'] is int ? json['idsv'] : int.tryParse(json['idsv']?.toString() ?? '') ?? 0,
      hocKy: json['hoc_ky'] is int ? json['hoc_ky'] : int.tryParse(json['hoc_ky']?.toString() ?? '') ?? 0,
      namHoc: json['nam_hoc']?.toString() ?? '',
      diemRl: json['diem_rl'] is int ? json['diem_rl'] : int.tryParse(json['diem_rl']?.toString() ?? '') ?? 0,
    );
  }

  // Phân loại xếp loại rèn luyện
  String get xepLoai {
    if (diemRl >= 90) return 'Xuất sắc';
    if (diemRl >= 80) return 'Tốt';
    if (diemRl >= 65) return 'Khá';
    if (diemRl >= 50) return 'Trung bình';
    if (diemRl >= 35) return 'Yếu';
    return 'Kém';
  }
}
