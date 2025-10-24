class UserModel {
  final String mssv;
  final String name;

  UserModel({required this.mssv, required this.name});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      mssv: json['mssv'],
      name: json['name'],
    );
  }
}
