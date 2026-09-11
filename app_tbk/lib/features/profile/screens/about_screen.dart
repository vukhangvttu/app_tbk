import 'package:flutter/material.dart';
import 'package:flutter/material.dart';

// ==================== ABOUT APP SCREEN ====================

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Về ứng dụng',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.5),
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // App Logo & Name
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primaryColor.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.apps_rounded,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'My Awesome App',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    'Phiên bản 1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // Features Section
          _buildSectionTitle('Tính năng chính', isDark),
          const SizedBox(height: 16),
          _buildFeatureCard(
            icon: Icons.speed_rounded,
            title: 'Hiệu suất cao',
            description: 'Tối ưu hóa để mang lại trải nghiệm mượt mà',
            isDark: isDark,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.security_rounded,
            title: 'Bảo mật tuyệt đối',
            description: 'Dữ liệu được mã hóa và bảo vệ an toàn',
            isDark: isDark,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.cloud_sync_rounded,
            title: 'Đồng bộ đám mây',
            description: 'Truy cập dữ liệu mọi lúc, mọi nơi',
            isDark: isDark,
            color: Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            icon: Icons.palette_rounded,
            title: 'Giao diện đẹp mắt',
            description: 'Thiết kế hiện đại, dễ sử dụng',
            isDark: isDark,
            color: Colors.orange,
          ),
          const SizedBox(height: 32),

          // Important Notes
          _buildSectionTitle('Lưu ý quan trọng', isDark),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (isDark ? Colors.amber[900] : Colors.amber[50])
                  ?.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? Colors.amber[800] : Colors.amber[200])!,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: isDark ? Colors.amber[300] : Colors.amber[800],
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Điều khoản sử dụng',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.amber[200] : Colors.amber[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildNoteItem(
                  'Bảo vệ thông tin cá nhân của bạn',
                  isDark,
                ),
                _buildNoteItem(
                  'Không chia sẻ mật khẩu với người khác',
                  isDark,
                ),
                _buildNoteItem(
                  'Cập nhật ứng dụng thường xuyên',
                  isDark,
                ),
                _buildNoteItem(
                  'Đọc kỹ chính sách bảo mật',
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Developer Info
          _buildSectionTitle('Thông tin phát triển', isDark),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : Colors.grey[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  icon: Icons.code_rounded,
                  label: 'Phát triển bởi',
                  value: 'Your Company',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  value: 'support@yourapp.com',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.language_rounded,
                  label: 'Website',
                  value: 'www.yourapp.com',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Phát hành',
                  value: 'Tháng 12, 2024',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Copyright
          Center(
            child: Text(
              '© 2024 Your Company. All rights reserved.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : Colors.black87,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteItem(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: isDark ? Colors.amber[300] : Colors.amber[700],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.amber[200] : Colors.amber[900],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}