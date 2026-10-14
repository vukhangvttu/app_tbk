class CourseGrade {
  final String tenMon;
  final int soTinChi;
  final String ngayThi;
  final int hocKy;
  final String nienKhoa;
  final double diemGiuaKy;
  final double diemCuoiKy;
  final String ngayCapNhat;
  final String ghiChuL1;

  CourseGrade({
    required this.tenMon,
    required this.soTinChi,
    required this.ngayThi,
    required this.hocKy,
    required this.nienKhoa,
    required this.diemGiuaKy,
    required this.diemCuoiKy,
    required this.ngayCapNhat,
    required this.ghiChuL1,
  });

  factory CourseGrade.fromJson(Map<String, dynamic> json) {
    return CourseGrade(
      tenMon: json['ten_mon']?.toString() ?? '',
      soTinChi: json['so_tin_chi'] is int ? json['so_tin_chi'] : int.tryParse(json['so_tin_chi']?.toString() ?? '') ?? 0,
      ngayThi: json['ngay_thi']?.toString() ?? '',
      hocKy: json['hoc_ky'] is int ? json['hoc_ky'] : int.tryParse(json['hoc_ky']?.toString() ?? '') ?? 0,
      nienKhoa: json['nien_khoa']?.toString() ?? '',
      diemGiuaKy: json['diem_giua_ky'] is num ? (json['diem_giua_ky'] as num).toDouble() : double.tryParse(json['diem_giua_ky']?.toString() ?? '') ?? 0.0,
      diemCuoiKy: json['diem_cuoi_ky'] is num ? (json['diem_cuoi_ky'] as num).toDouble() : double.tryParse(json['diem_cuoi_ky']?.toString() ?? '') ?? 0.0,
      ngayCapNhat: json['ngay_cap_nhat']?.toString() ?? '',
      ghiChuL1: json['ghi_chu_l1']?.toString() ?? '',
    );
  }

  double get diemTongKet {
    return double.parse((diemGiuaKy + diemCuoiKy).toStringAsFixed(1));
  }

  String get diemChu {
    final diem = diemTongKet;
    if (diem >= 8.5) return 'A';
    if (diem >= 7.0) return 'B';
    if (diem >= 5.5) return 'C';
    if (diem >= 4.0) return 'D';
    return 'F';
  }

  String get xepLoai {
    final diem = diemTongKet;
    if (diem >= 8.5) return 'Giỏi';
    if (diem >= 7.0) return 'Khá';
    if (diem >= 5.5) return 'Trung bình';
    if (diem >= 4.0) return 'Trung bình yếu';
    return 'Kém';
  }
}
