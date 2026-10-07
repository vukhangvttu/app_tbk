plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.app_tbk"
    compileSdk = 36
    ndkVersion = "27.0.12077973" // ✅ Dùng NDK mới theo yêu cầu plugin

    defaultConfig {
        applicationId = "com.example.app_tbk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments("-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
                cppFlags("-Wl,-z,max-page-size=16384")
            }
        }
    }

    // ✅ Bật Java 17+ và desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        getByName("release") {
            // ✅ Ký APK release bằng debug key để có thể cài đặt trực tiếp trên mọi điện thoại
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            isDebuggable = false
        }
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
            isDebuggable = true
        }

    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ Thêm thư viện desugar để hỗ trợ API Java 8+
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-messaging")
}


apply(plugin = "com.google.gms.google-services")


//plugins {
//    id("com.android.application")
//    id("kotlin-android")
//    id("dev.flutter.flutter-gradle-plugin")
//    id("com.google.gms.google-services")
//}
//
//android {
//    namespace = "com.example.app_tbk"
//    compileSdk = 35 // ✅ Cập nhật lên SDK 35 để tương thích với các plugin
//
//    compileOptions {
//        sourceCompatibility = JavaVersion.VERSION_11 // ✅ Sử dụng Java 11
//        targetCompatibility = JavaVersion.VERSION_11 // ✅ Sử dụng Java 11
//        isCoreLibraryDesugaringEnabled = true // ✅ Bật core library desugaring
//    }
//
//    kotlinOptions {
//        jvmTarget = "11" // ✅ Sử dụng JVM target 11
//    }
//
//    defaultConfig {
//        applicationId = "com.example.app_tbk"
//        minSdk = 21
//        targetSdk = 34
//        versionCode = 1
//        versionName = "1.0.0"
//
//        // ✅ Chỉ build cho kiến trúc phổ biến (giảm ~40% dung lượng)
//        ndk {
//            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
//        }
//    }
//
//    buildTypes {
//        release {
//            // ✅ Bật shrinking, obfuscation, optimization
//            isMinifyEnabled = true
//            isShrinkResources = true
//
//            proguardFiles(
//                getDefaultProguardFile("proguard-android-optimize.txt"),
//                "proguard-rules.pro"
//            )
//
//            // ✅ Tối ưu native libraries
//            ndk {
//                debugSymbolLevel = "NONE"
//            }
//        }
//
//        debug {
//            isMinifyEnabled = false
//            isShrinkResources = false
//        }
//    }
//
//    // ✅ Tách APK theo kiến trúc (giảm 50-60% kích thước mỗi APK)
//    splits {
//        abi {
//            isEnable = true
//            reset()
//            include("armeabi-v7a", "arm64-v8a", )
//            isUniversalApk = true // Tạo thêm 1 APK universal cho Play Store
//        }
//    }
//}
//
//dependencies {
//    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.7.10")
//    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4") // ✅ Thêm dependency desugaring
//
//    // Firebase BOM để đồng bộ version
//    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
//    implementation("com.google.firebase:firebase-messaging-ktx")
//    implementation("com.google.firebase:firebase-config-ktx")
//}
