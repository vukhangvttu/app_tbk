# Flutter Engine & Plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# App Package
-keep class com.example.app_tbk.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google ML Kit & Camera
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }

# Easy Localization / Gson / Jackson
-keep class com.google.gson.** { *; }
-keep class com.fasterxml.jackson.** { *; }

# Security checker
-keep class com.example.secure_app.** { *; }

# Preserve Native Method Names & JS Interface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
    native <methods>;
}

# Suppress missing Play Core classes referenced by Flutter Embedding
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**