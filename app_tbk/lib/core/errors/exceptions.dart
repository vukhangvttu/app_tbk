/// Exception ném ra khi thiết bị không có kết nối Internet hoặc không kết nối được tới server
class NoInternetException implements Exception {
  final String message;

  NoInternetException([
    this.message = 'Không có kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.',
  ]);

  @override
  String toString() => message;
}
