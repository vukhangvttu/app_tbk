# Keep security checker
-keep class com.example.secure_app.** { *; }

# Obfuscate code
-repackageclasses
-allowaccessmodification
-optimizationpasses 5