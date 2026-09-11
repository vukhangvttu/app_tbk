class UserProfile {
  final String id;
  final String userId;
  final String hoTen;
  final String ngaySinh;
  final String gioiTinh;
  final String mssv;
  final String email;
  final String sdt;
  final String lop;
  final String khoa;
  final String khoaHoc;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.userId,
    required this.hoTen,
    required this.ngaySinh,
    required this.gioiTinh,
    required this.mssv,
    required this.email,
    required this.sdt,
    required this.lop,
    required this.khoa,
    required this.khoaHoc,
    this.avatarUrl,
  });

  /// Tạo từ JSON (map -> object)
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      hoTen: json['ho_ten'] ?? '',
      ngaySinh: json['ngay_sinh'] ?? '',
      gioiTinh: json['gioi_tinh'] ?? '',
      mssv: json['mssv'] ?? '',
      email: json['email'] ?? '',
      sdt: json['sdt'] ?? '',
      lop: json['lop'] ?? '',
      khoa: json['khoa'] ?? '',
      khoaHoc: json['khoa_hoc'] ?? '',
      avatarUrl: json['avatar_url'],
    );
  }

  /// Chuyển sang JSON (object -> map)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'ho_ten': hoTen,
      'ngay_sinh': ngaySinh,
      'gioi_tinh': gioiTinh,
      'mssv': mssv,
      'email': email,
      'sdt': sdt,
      'lop': lop,
      'khoa': khoa,
      'khoa_hoc': khoaHoc,
      'avatar_url': avatarUrl,
    };
  }
}
