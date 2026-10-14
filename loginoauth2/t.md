Đã áp dụng thành công giao diện điều hướng (Google Maps Navigation UI) sử dụng Google Routes API sau khi đăng nhập thành công!
📋 Các thay đổi đã được thực hiện:
1.
Tạo Service tính tuyến đường (  lib/services/directions_service.dart):
◦
Tích hợp Google Routes API mới (computeRoutes) hỗ trợ phương tiện TWO_WHEELER (xe máy) thật.
◦
Giải mã Polyline bằng package google_polyline_algorithm.
◦
Bắt buộc dùng X-Goog-FieldMask để tối ưu chi phí và băng thông.
2.
Tạo Màn hình điều hướng (  lib/screens/navigation_screen.dart):
◦
Bản đồ Google Maps với các nút điều khiển, thanh tìm kiếm chọn điểm đi/đến.
◦
Thanh chọn phương tiện (Ô tô, Xe máy, Đi bộ, Xe buýt).
◦
Bảng thông tin chuyến đi kéo vuốt (Bottom Sheet) hiển thị thời gian, khoảng cách và danh sách chỉ đường từng bước với icon hướng rẽ thích hợp.
◦
Tích hợp Avatar và nút Đăng xuất ngay tại góc thanh tìm kiếm.
3.
Cập nhật luồng ứng dụng (  lib/main.dart &   lib/screens/login_screen.dart):
◦
AuthGate tự động chuyển người dùng vào NavigationScreen sau khi xác thực thành công.
◦
Tự động điều hướng ngay khi bấm đăng nhập thành công từ LoginScreen.
4.
Cập nhật Android Manifest (  android/app/src/main/AndroidManifest.xml):
◦
Thêm thẻ meta-data cho Google Maps API Key:
XML
<meta-data
android:name="com.google.android.geo.API_KEY"
android:value="YOUR_API_KEY"/>
🔑 Lưu ý trước khi chạy app:
Thay YOUR_API_KEY bằng API Key thật của bạn (đã bật Maps SDK for Android và Routes API trên Google Cloud Console) tại 2 vị trí:
1.
lib/screens/navigation_screen.dart (dòng _apiKey).
2.
android/app/src/main/AndroidManifest.xml (dòng android:value).