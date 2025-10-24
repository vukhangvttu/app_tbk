class ClassSchedule {
  final String monHoc;
  final DateTime ngayHoc;
  final String phong;
  final String giangVien;

  ClassSchedule({
    required this.monHoc,
    required this.ngayHoc,
    required this.phong,
    required this.giangVien,
  });

  factory ClassSchedule.fromJson(Map<String, dynamic> json) {
    return ClassSchedule(
      monHoc: json['monHoc'],
      ngayHoc: DateTime.parse(json['ngayHoc']),
      phong: json['phong'],
      giangVien: json['giangVien'],
    );
  }
}
