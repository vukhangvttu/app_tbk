class AppVersionModel {
  final String version;
  final String platform;
  final String minVersion;
  final bool forceUpdate;
  final String updateTitle;
  final String updateDesc;
  final String downloadUrl;
  final String releaseNotes;
  final String? updatedAt;

  AppVersionModel({
    required this.version,
    required this.platform,
    required this.minVersion,
    required this.forceUpdate,
    required this.updateTitle,
    required this.updateDesc,
    required this.downloadUrl,
    required this.releaseNotes,
    this.updatedAt,
  });

  factory AppVersionModel.fromJson(Map<String, dynamic> json) {
    return AppVersionModel(
      version: json['version']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      minVersion: json['minVersion']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      updateTitle: json['updateTitle']?.toString() ?? 'Cập nhật ứng dụng',
      updateDesc: json['updateDesc']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      releaseNotes: json['releaseNotes']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'platform': platform,
      'minVersion': minVersion,
      'forceUpdate': forceUpdate,
      'updateTitle': updateTitle,
      'updateDesc': updateDesc,
      'downloadUrl': downloadUrl,
      'releaseNotes': releaseNotes,
      'updatedAt': updatedAt,
    };
  }
}
