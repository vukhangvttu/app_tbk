import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../services/profile_service.dart';

// ==================== FEEDBACK SCREEN ====================
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackController = TextEditingController();
  final List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String _selectedCategory = 'Góp ý chung';

  final List<String> _categories = [
    'Góp ý chung',
    'Báo lỗi',
    'Yêu cầu tính năng',
    'Cải thiện UI/UX',
    'Khác',
  ];

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.length + _selectedImages.length > 5) {
        _showElegantSnackBar(
          context: context,
          message: 'Chỉ được chọn tối đa 5 hình ảnh',
          icon: Icons.warning_rounded,
          isError: true,
        );
        return;
      }

      setState(() {
        _selectedImages.addAll(images.map((img) => File(img.path)));
      });
    } catch (e) {
      _showElegantSnackBar(
        context: context,
        message: 'Không thể chọn hình ảnh',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ProfileService.submitFeedback(
        loaiPhanHoi: _selectedCategory,
        noiDung: _feedbackController.text.trim(),
        hinhAnh: _selectedImages,
      );

      if (!mounted) return;

      Navigator.pop(context);

      _showElegantSnackBar(
        context: context,
        message: 'Cảm ơn bạn đã gửi phản hồi!',
        icon: Icons.check_circle_rounded,
        isError: false,
      );

      _feedbackController.clear();
      setState(() {
        _selectedImages.clear();
        _selectedCategory = 'Góp ý chung';
      });
    } catch (e) {
      if (!mounted) return;

      String errorMessage = e.toString().replaceFirst('Exception: ', '').trim();
      if (errorMessage.isEmpty) {
        errorMessage = 'Không thể gửi phản hồi, vui lòng thử lại';
      }

      _showElegantSnackBar(
        context: context,
        message: errorMessage,
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showElegantSnackBar({
    required BuildContext context,
    required String message,
    required IconData icon,
    required bool isError,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isError
                  ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                  : [const Color(0xFF10B981), const Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isError ? const Color(0xFFDC2626) : const Color(0xFF10B981))
                    .withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isError ? 'Thất bại' : 'Thành công',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(milliseconds: 3000),
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = theme.primaryColor;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subTitleColor = isDark ? const Color(0xFF94A3B8) : Colors.grey[600];
    final sectionLabelColor = isDark ? const Color(0xFFE2E8F0) : Colors.grey[800];
    final cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.grey[50];
    final cardBorderColor = isDark ? const Color(0xFF334155) : Colors.grey[300]!;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Gửi phản hồi',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            color: titleColor,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20, color: titleColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withValues(alpha: isDark ? 0.2 : 0.1),
                    primaryColor.withValues(alpha: isDark ? 0.1 : 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryColor.withValues(alpha: isDark ? 0.3 : 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: isDark ? 0.25 : 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.feedback_rounded,
                      color: isDark ? Colors.white : primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ý kiến của bạn',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Giúp chúng tôi cải thiện ứng dụng',
                          style: TextStyle(
                            fontSize: 13,
                            color: subTitleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Category Selection
            Text(
              'Loại phản hồi',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionLabelColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    color: titleColor,
                  ),
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(
                        category,
                        style: TextStyle(color: titleColor),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCategory = value);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Feedback Content
            Text(
              'Nội dung phản hồi',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionLabelColor,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _feedbackController,
              maxLines: 6,
              maxLength: 500,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập nội dung phản hồi';
                }
                if (value.trim().length < 10) {
                  return 'Nội dung phải có ít nhất 10 ký tự';
                }
                return null;
              },
              style: TextStyle(
                fontSize: 15,
                color: titleColor,
              ),
              decoration: InputDecoration(
                hintText: 'Chia sẻ ý kiến, góp ý hoặc báo lỗi của bạn...',
                hintStyle: TextStyle(
                  color: isDark ? const Color(0xFF64748B) : Colors.grey[400],
                ),
                counterStyle: TextStyle(
                  color: subTitleColor,
                ),
                filled: true,
                fillColor: cardBgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cardBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primaryColor, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFDC2626)),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 24),

            // Images Section
            Text(
              'Hình ảnh đính kèm (Tùy chọn)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: sectionLabelColor,
              ),
            ),
            const SizedBox(height: 8),

            // Image Grid
            if (_selectedImages.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ..._selectedImages.asMap().entries.map((entry) {
                      return _buildImagePreview(entry.value, entry.key, isDark);
                    }),
                    if (_selectedImages.length < 5) _buildAddImageButton(isDark),
                  ],
                ),
              )
            else
              _buildAddImageButton(isDark),

            const SizedBox(height: 12),
            Text(
              'Tối đa 5 hình ảnh • PNG, JPG, JPEG',
              style: TextStyle(
                fontSize: 12,
                color: subTitleColor,
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: primaryColor.withValues(
                    alpha: isDark ? 0.35 : 0.6,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Gửi phản hồi',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(File image, int index, bool isDark) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey[300]!,
            ),
            image: DecorationImage(
              image: FileImage(image),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddImageButton(bool isDark) {
    final iconTextColor = isDark ? const Color(0xFF94A3B8) : Colors.grey[500];

    return GestureDetector(
      onTap: _pickImages,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : Colors.grey[300]!,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_rounded,
              color: iconTextColor,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              'Thêm ảnh',
              style: TextStyle(
                fontSize: 12,
                color: iconTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
