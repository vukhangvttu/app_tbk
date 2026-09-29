import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoTenController = TextEditingController();
  final _ngaySinhController = TextEditingController();
  final _gioiTinhController = TextEditingController();
  final _mssvController = TextEditingController();
  final _emailController = TextEditingController();
  final _sdtController = TextEditingController();
  final _lopController = TextEditingController();
  final _khoaHocController = TextEditingController();

  File? _selectedImage;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedGender = 'male';
  final ImagePicker _picker = ImagePicker();
  bool _hasAvatar = false;
  int _avatarTimestamp = DateTime.now().millisecondsSinceEpoch;
  String _userId = '';
  late Future<Map<String, String>> _authHeadersFuture;

  String? _normalizeGender(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'male' || lower == 'nam') return 'male';
    if (lower == 'female' || lower == 'nữ' || lower == 'nu') return 'female';
    if (lower == 'other' || lower == 'khác' || lower == 'khac') return 'other';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _authHeadersFuture = ProfileService.getAuthHeaders();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      setState(() => _isLoading = true);
      final profile = await ProfileService.fetchProfile(context);
      if (profile == null) {
        final mssv = (await AuthService.getSavedMssv())?.toString();
        if (mssv == null || mssv.isEmpty) {
          throw Exception('Không tìm thấy mã số sinh viên trong bộ nhớ tạm');
        }
        _mssvController.text = mssv;
        _emailController.text = mssv;
        _hasAvatar = false;
      } else {
        _hoTenController.text = profile.hoTen ?? '';
        _ngaySinhController.text = profile.ngaySinh ?? '';
        _selectedGender = _normalizeGender(profile.gioiTinh);
        _gioiTinhController.text = profile.gioiTinh ?? '';
        _mssvController.text = profile.mssv ?? '';
        _emailController.text = (profile.email != null ? profile.email?.split('@').first : '')!;
        _sdtController.text = profile.sdt ?? '';
        _lopController.text = profile.lop ?? '';
        _khoaHocController.text = profile.khoaHoc ?? '';
        _hasAvatar = true;
      }
      final userId = await AuthService.getUserId() ?? '';
      setState(() {
        _isLoading = false;
        _userId = userId;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tải thông tin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi chọn ảnh: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_hoTenController.text.trim().isEmpty ||
        _mssvController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _sdtController.text.trim().isEmpty ||
        _lopController.text.trim().isEmpty ||
        _ngaySinhController.text.trim().isEmpty ||
        _selectedGender?.trim().isEmpty == true ||
        _khoaHocController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Vui lòng nhập đầy đủ thông tin trước khi lưu.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isSaving = true);

      final updatedProfile = await ProfileService.updateProfile(
        context: context,
        hoTen: _hoTenController.text.trim(),
        ngaySinh: _ngaySinhController.text.trim(),
        gioiTinh: _selectedGender!,
        mssv: _mssvController.text.trim(),
        email: _emailController.text.trim(),
        sdt: _sdtController.text.trim(),
        lop: _lopController.text.trim(),
        khoaHoc: _khoaHocController.text.trim(),
        avatarFile: _selectedImage,
      );

      if (_selectedImage != null) {
        setState(() {
          _avatarTimestamp = DateTime.now().millisecondsSinceEpoch;
          _hasAvatar = true;
          _selectedImage = null;
        });
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cập nhật thông tin thành công', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lỗi khi cập nhật: $e',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _ngaySinhController.dispose();
    _gioiTinhController.dispose();
    _mssvController.dispose();
    _emailController.dispose();
    _sdtController.dispose();
    _lopController.dispose();
    _khoaHocController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chỉnh sửa thông tin',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildAvatarSection(isDark, primaryColor),
              const SizedBox(height: 8),
              Text(
                'Nhấn để thay đổi ảnh',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),

              _buildTextField(
                controller: _hoTenController,
                label: 'Họ và tên',
                icon: Icons.person_outline_rounded,
                capitalizeWords: true,
                hintText: 'Nhập họ và tên đầy đủ',
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _ngaySinhController,
                label: 'Ngày sinh',
                icon: Icons.cake_outlined,
                hintText: 'dd/MM/yyyy',
                isDate: true,
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildGenderField(
                label: 'Giới tính',
                icon: Icons.wc_rounded,
                value: _selectedGender,
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Nam')),
                  DropdownMenuItem(value: 'female', child: Text('Nữ')),
                  DropdownMenuItem(value: 'other', child: Text('Khác')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _mssvController,
                label: 'MSSV',
                icon: Icons.badge_outlined,
                keyboardType: TextInputType.number,
                hintText: 'Nhập mã số sinh viên',
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                hintText: 'Nhập MSSV',
                suffixText: '@stu.vttu.edu.vn',
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _sdtController,
                label: 'Số điện thoại',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hintText: 'Nhập số điện thoại',
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _lopController,
                label: 'Lớp',
                icon: Icons.class_outlined,
                hintText: 'CNTT, Y KHOA, ...',
                capitalizeWords: true,
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _khoaHocController,
                label: 'Khóa',
                icon: Icons.school_outlined,
                hintText: 'K17, K18, ...',
                capitalizeWords: true,
                isDark: isDark,
              ),
              const SizedBox(height: 32),

              _buildSaveButton(isDark, primaryColor),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // Gender Field - Giữ nguyên style hiện tại
  Widget _buildGenderField({
    required String label,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    final effectiveValue = (value != null && items.any((item) => item.value == value))
        ? value
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[300] : Colors.grey[800],
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey[300]!,
            ),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: effectiveValue,
            items: items,
            onChanged: onChanged,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                size: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            isExpanded: true,
            hint: Text(
              'Chọn giới tính',
              style: TextStyle(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // TextField - CẬP NHẬT ĐỂ ĐỒNG BỘ VỚI _buildGenderField
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    String? suffixText,
    String? hintText,
    bool capitalizeWords = false,
    bool isDate = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey[300] : Colors.grey[800],
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : Colors.grey[300]!,
            ),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: isDate ? TextInputType.datetime : keyboardType,
            inputFormatters: isDate
                ? [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
              _DateInputFormatter(),
            ]
                : null,
            textCapitalization: TextCapitalization.none,
            readOnly: isDate,
            onTap: isDate
                ? () {
              FocusScope.of(context).requestFocus(FocusNode());
              _selectDate(controller);
            }
                : null,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            onChanged: (value) {
              if (capitalizeWords && !isDate) {
                final formatted = _capitalizeEachWord(value);
                if (formatted != value) {
                  final cursorPos = controller.selection;
                  controller.value = TextEditingValue(
                    text: formatted,
                    selection: cursorPos,
                  );
                }
              }
            },
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                icon,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                size: 20,
              ),
              suffixIcon: isDate
                  ? Icon(
                Icons.calendar_today_rounded,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                size: 18,
              )
                  : null,
              suffixText: suffixText,
              suffixStyle: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập $label';
              }

              if (isDate) {
                final regex = RegExp(r'^\d{2}/\d{2}/\d{4}$');
                if (!regex.hasMatch(value)) {
                  return 'Định dạng: dd/MM/yyyy';
                }
                try {
                  final parts = value.split('/');
                  final day = int.parse(parts[0]);
                  final month = int.parse(parts[1]);
                  final year = int.parse(parts[2]);
                  if (day < 1 || day > 31) return 'Ngày không hợp lệ';
                  if (month < 1 || month > 12) return 'Tháng không hợp lệ';
                  if (year < 1900 || year > DateTime.now().year) {
                    return 'Năm không hợp lệ';
                  }

                  final date = DateTime(year, month, day);
                  if (date.day != day || date.month != month || date.year != year) {
                    return 'Ngày không tồn tại';
                  }
                } catch (e) {
                  return 'Ngày sinh không hợp lệ';
                }
              }

              // Validation cho MSSV
              if (label == 'MSSV' && value.isNotEmpty) {
                if (!RegExp(r'^[0-9]{10,11}$').hasMatch(value)) {
                  return 'Mã số không hợp lệ';
                }
              }

              // Validation cho số điện thoại
              if (label == 'Số điện thoại' && value.isNotEmpty) {
                if (!RegExp(r'^[0-9]{10,11}$').hasMatch(value)) {
                  return 'Số điện thoại không hợp lệ';
                }
              }

              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarSection(bool isDark, Color primaryColor) {
    final String avatarEndpoint =
        '${ApiConstants.baseUrl}/upload/avatar/thumb-url/${_userId}?t=$_avatarTimestamp';

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isDark
                    ? [Colors.grey[800]!, Colors.grey[700]!]
                    : [Colors.grey[200]!, Colors.grey[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: primaryColor,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: _selectedImage != null
                  ? Image.file(
                _selectedImage!,
                fit: BoxFit.cover,
                key: ValueKey(_selectedImage!.path),
              )
                  : _hasAvatar
                  ? FutureBuilder<Map<String, String>>(
                future: _authHeadersFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }

                  return Image.network(
                    avatarEndpoint,
                    headers: snapshot.data,
                    fit: BoxFit.cover,
                    key: ValueKey(avatarEndpoint),
                    cacheWidth: null,
                    cacheHeight: null,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return _buildDefaultAvatar(isDark);
                    },
                  );
                },
              )
                  : _buildDefaultAvatar(isDark),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF64B5F6), const Color(0xFF42A5F5)]
                      : [const Color(0xFF42A5F5), const Color(0xFF1E88E5)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(bool isDark) {
    return Icon(
      Icons.person_rounded,
      size: 60,
      color: isDark ? Colors.grey[600] : Colors.grey[400],
    );
  }

  Widget _buildSaveButton(bool isDark, Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1565C0), const Color(0xFF1E88E5)]
                : [const Color(0xFF42A5F5), const Color(0xFF1976D2)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveProfile,
          icon: _isSaving
              ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
          label: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isSaving
                ? const Text(
              'Đang lưu...',
              key: ValueKey('saving'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            )
                : const Text(
              'Cập nhật thông tin',
              key: ValueKey('normal'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  String _capitalizeEachWord(String text) {
    return text
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: isDark ? Colors.grey[850]! : Colors.white,
              onSurface: isDark ? Colors.white : Colors.black87,
            ),
            dialogBackgroundColor: isDark ? Colors.grey[850] : Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(picked);
    }
  }
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final text = newValue.text.replaceAll('/', '');
    if (text.isEmpty) return newValue.copyWith(text: '');

    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(text[i]);
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}