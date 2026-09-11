import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

void showNotificationDialog(
    BuildContext context,
    String title,
    String message, {
      bool isSuccess = true,
    }) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 8,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _getGradientColors(isDarkMode, isSuccess),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSuccess
                  ? (isDarkMode ? Colors.blue.withOpacity(0.3) : Colors.blue.withOpacity(0.2))
                  : (isDarkMode ? Colors.red.withOpacity(0.3) : Colors.red.withOpacity(0.2)),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Message
              Text(
                message,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: isSuccess
                        ? (isDarkMode ? Colors.blue[700] : Colors.blue[600])
                        : (isDarkMode ? Colors.red[700] : Colors.red[600]),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'common.close'.tr(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

List<Color> _getGradientColors(bool isDarkMode, bool isSuccess) {
  if (isSuccess) {
    // Success colors
    if (isDarkMode) {
      return [
        const Color(0xFF1E3A8A), // Deep blue
        const Color(0xFF1E40AF), // Rich blue
        const Color(0xFF2563EB), // Bright blue
      ];
    } else {
      return [
        const Color(0xFF3B82F6), // Bright blue
        const Color(0xFF2563EB), // Medium blue
        const Color(0xFF1D4ED8), // Deep blue
      ];
    }
  } else {
    // Error colors
    if (isDarkMode) {
      return [
        const Color(0xFF7F1D1D), // Deep red
        const Color(0xFF991B1B), // Rich red
        const Color(0xFFB91C1C), // Bright red
      ];
    } else {
      return [
        const Color(0xFFEF4444), // Bright red
        const Color(0xFFDC2626), // Medium red
        const Color(0xFFC81E1E), // Deep red
      ];
    }
  }
}
