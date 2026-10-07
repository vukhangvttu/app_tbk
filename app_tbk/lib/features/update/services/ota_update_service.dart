import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:app_tbk/config/api_constants.dart';

class OtaUpdateService {
  /// Hiển thị Dialog tiến trình và tiến hành tải file APK
  static void startDownloadAndInstall(BuildContext context, String downloadUrl, bool force) {
    showDialog(
      context: context,
      barrierDismissible: false, // Bắt buộc đợi tải xong
      builder: (context) => _DownloadProgressDialog(
        downloadUrl: downloadUrl,
        isForceUpdate: force,
      ),
    );
  }
}

/// Widget hiển thị tiến trình tải (Progress Bar)
class _DownloadProgressDialog extends StatefulWidget {
  final String downloadUrl;
  final bool isForceUpdate;

  const _DownloadProgressDialog({
    Key? key,
    required this.downloadUrl,
    required this.isForceUpdate,
  }) : super(key: key);

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0.0;
  String _statusText = "Đang chuẩn bị tải...";
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      // Lấy thư mục cache an toàn để lưu file
      final dir = await getExternalStorageDirectory();
      final savePath = '${dir?.path}/update_app.apk';

      // Xử lý base URL nếu đường dẫn tải xuống là relative path
      String url = widget.downloadUrl;
      
      // MẸO SỬA LỖI TRƯỜNG HỢP DATABASE ĐANG LƯU SẴN GIÁ TRỊ CŨ (127.0.0.1)
      if (url.contains('127.0.0.1') || url.contains('localhost')) {
         // Cắt bỏ phần domain cũ, chỉ lấy endpoint phía sau
         final uri = Uri.parse(url);
         // Nếu uri.path bắt đầu bằng /api/v1 thì cần tránh bị lặp lại vì baseUrl đã có sẵn /student-calendar/api/v1
         String path = uri.path;
         if (path.startsWith('/api/v1')) {
           path = path.replaceFirst('/api/v1', '');
         }
         url = '${ApiConstants.baseUrl}$path';
      }

      // Fix lỗi: Đôi khi API Go trả về url tuyệt đối nhưng baseUrl có chứa subdirectory 
      // (ví dụ /student-calendar/api/v1). Chúng ta cần cẩn thận khi nối chuỗi.
      if (!url.startsWith('http')) {
        // Kiểm tra nếu url từ server bắt đầu bằng '/' và baseUrl cũng kết thúc bằng '/'
        if (url.startsWith('/') && ApiConstants.baseUrl.endsWith('/')) {
           url = '${ApiConstants.baseUrl}${url.substring(1)}';
        } else if (!url.startsWith('/') && !ApiConstants.baseUrl.endsWith('/')) {
           url = '${ApiConstants.baseUrl}/$url';
        } else {
           url = '${ApiConstants.baseUrl}$url';
        }
      }
      
      debugPrint('Đang tải APK từ URL: $url'); // Thêm log in ra url

      // Bắt buộc dùng GET cho việc tải file thay vì để Dio tự gọi HEAD
      final options = Options(
        method: 'GET',
        responseType: ResponseType.bytes,
      );

      await _dio.download(
        url,
        savePath,
        options: options,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
              _statusText = "Đang tải... ${( _progress * 100).toStringAsFixed(1)}%";
            });
          }
        },
      );

      setState(() {
        _statusText = "Tải xong! Đang mở cài đặt...";
      });

      // Mở file APK để cài đặt
      final result = await OpenFilex.open(savePath);

      if (result.type != ResultType.done) {
        setState(() {
          _statusText = "Lỗi mở file cài đặt: ${result.message}";
        });
      } else {
        // Tắt dialog nếu mở cài đặt thành công (nếu không phải force update)
        if (!widget.isForceUpdate && mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _statusText = "Lỗi khi tải file. Vui lòng thử lại sau.";
      });
      debugPrint("Download Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đang cập nhật ứng dụng'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 16),
          Text(_statusText),
        ],
      ),
      actions: [
        // Chỉ hiện nút Đóng nếu tải lỗi hoặc không bắt buộc cập nhật
        if (!widget.isForceUpdate || _statusText.contains("Lỗi"))
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
      ],
    );
  }
}

