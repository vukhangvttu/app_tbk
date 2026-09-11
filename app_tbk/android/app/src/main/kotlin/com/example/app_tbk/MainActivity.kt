//package com.example.app_tbk
//
//import io.flutter.embedding.android.FlutterFragmentActivity
//
//class MainActivity : FlutterFragmentActivity()


package com.example.app_tbk

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.example.app_tbk/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRootNative" -> {
                    val isRooted = checkRootAccess()
                    result.success(isRooted)
                }
                "checkInstalledApps" -> {
                    val packageNames = call.argument<List<String>>("packages")
                    val found = checkInstalledPackages(packageNames ?: emptyList())
                    result.success(found)
                }
                "checkDangerousProps" -> {
                    val isDangerous = checkDangerousSystemProperties()
                    result.success(isDangerous)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Kiểm tra Root access bằng nhiều phương pháp Native
     */
    private fun checkRootAccess(): Boolean {
        return checkRootMethod1() ||
                checkRootMethod2() ||
                checkRootMethod3() ||
                checkForBusyBoxBinary() ||
                checkForSuBinary() ||
                checkSuExists() ||
                checkForRWPaths()
    }

    /**
     * Method 1: Kiểm tra Su binary
     */
    private fun checkRootMethod1(): Boolean {
        val buildTags = Build.TAGS
        return buildTags != null && buildTags.contains("test-keys")
    }

    /**
     * Method 2: Kiểm tra quyền truy cập /system
     */
    private fun checkRootMethod2(): Boolean {
        val paths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su",
            "/su/bin/su"
        )

        return paths.any { File(it).exists() }
    }

    /**
     * Method 3: Thử execute su command
     */
    private fun checkRootMethod3(): Boolean {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            val input = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
            input.readLine() != null
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    /**
     * Kiểm tra BusyBox binary
     */
    private fun checkForBusyBoxBinary(): Boolean {
        return checkForBinary("busybox")
    }

    /**
     * Kiểm tra Su binary chi tiết
     */
    private fun checkForSuBinary(): Boolean {
        return checkForBinary("su")
    }

    /**
     * Kiểm tra binary cụ thể
     */
    private fun checkForBinary(filename: String): Boolean {
        val paths = arrayOf(
            "/system/xbin/",
            "/system/bin/",
            "/system/sbin/",
            "/sbin/",
            "/vendor/bin/",
            "/su/bin/",
            "/data/local/xbin/",
            "/data/local/bin/",
            "/system/sd/xbin/",
            "/system/bin/failsafe/",
            "/data/local/"
        )

        return paths.any { File(it + filename).exists() }
    }

    /**
     * Kiểm tra sự tồn tại của su
     */
    private fun checkSuExists(): Boolean {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val input = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
            input.readLine() != null
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    /**
     * Kiểm tra đường dẫn có quyền Read/Write
     */
    private fun checkForRWPaths(): Boolean {
        val paths = arrayOf(
            "/system",
            "/system/bin",
            "/system/sbin",
            "/system/xbin",
            "/vendor/bin",
            "/sbin",
            "/etc"
        )

        return paths.any {
            val file = File(it)
            file.exists() && file.canWrite()
        }
    }

    /**
     * Kiểm tra các packages đã cài đặt
     */
    private fun checkInstalledPackages(packageNames: List<String>): Boolean {
        val pm = packageManager
        return packageNames.any { packageName ->
            try {
                pm.getPackageInfo(packageName, 0)
                true
            } catch (e: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    /**
     * Kiểm tra dangerous system properties
     */
    private fun checkDangerousSystemProperties(): Boolean {
        val dangerousProps = mapOf(
            "ro.debuggable" to "1",
            "ro.secure" to "0"
        )

        return dangerousProps.any { (key, value) ->
            val propValue = getSystemProperty(key)
            propValue == value
        }
    }

    /**
     * Lấy system property
     */
    private fun getSystemProperty(propName: String): String? {
        return try {
            val process = Runtime.getRuntime().exec("getprop $propName")
            val input = java.io.BufferedReader(java.io.InputStreamReader(process.inputStream))
            input.readLine()
        } catch (e: Exception) {
            null
        }
    }
}