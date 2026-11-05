import UIKit
import Flutter
import GoogleMaps
import MachO

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let securityChannel = FlutterMethodChannel(
            name: "com.example.secure_app/security",
            binaryMessenger: controller.binaryMessenger
        )

        securityChannel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }

            switch call.method {
            case "checkJailbreakNative":
                let isJailbroken = self.isJailbroken()
                result(isJailbroken)
            case "checkCydiaURLScheme":
                let hasCydia = self.canOpenCydiaURL()
                result(hasCydia)
            case "checkSuspiciousFiles":
                let hasFiles = self.checkSuspiciousFiles()
                result(hasFiles)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        GMSServices.provideAPIKey("AIzaSyDCFhowDrauJ1_nL-5ltmWT1iA-MOvfbUU")
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /**
     * Kiểm tra Jailbreak bằng nhiều phương pháp
     */
    private func isJailbroken() -> Bool {
        return checkJailbreakMethod1() ||
               checkJailbreakMethod2() ||
               checkJailbreakMethod3() ||
               checkJailbreakMethod4() ||
               checkJailbreakMethod5() ||
               checkSymbolicLinks() ||
               checkFork() ||
               checkSystemFunction()
    }

    /**
     * Method 1: Kiểm tra sự tồn tại của các file/app Jailbreak
     */
    private func checkJailbreakMethod1() -> Bool {
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/stash",
            "/private/var/tmp/cydia.log",
            "/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/bin/bash",
            "/bin/sh",
            "/usr/bin/ssh",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            "/var/cache/apt",
            "/var/lib/apt",
            "/var/lib/cydia",
            "/usr/libexec/cydia",
            "/usr/bin/cycript",
            "/usr/local/bin/cycript",
            "/usr/lib/libcycript.dylib"
        ]

        return jailbreakPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /**
     * Method 2: Kiểm tra khả năng ghi file ngoài sandbox
     */
    private func checkJailbreakMethod2() -> Bool {
        let testString = "Jailbreak Test"
        let testPath = "/private/jailbreak_test.txt"

        do {
            try testString.write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true // Không nên ghi được
        } catch {
            return false // Bình thường sẽ bị lỗi
        }
    }

    /**
     * Method 3: Kiểm tra dylib đã bị inject
     */
    private func checkJailbreakMethod3() -> Bool {
        let suspiciousLibraries = [
            "SubstrateLoader.dylib",
            "SSLKillSwitch2.dylib",
            "SSLKillSwitch.dylib",
            "MobileSubstrate.dylib",
            "TweakInject.dylib",
            "CydiaSubstrate",
            "cynject",
            "CustomWidgetIcons",
            "PreferenceLoader",
            "RocketBootstrap",
            "WeeLoader",
            "zzzzLiberty.dylib"
        ]

        for i in 0..<_dyld_image_count() {
            if let imageName = _dyld_get_image_name(i) {
                let name = String(cString: imageName)
                if suspiciousLibraries.contains(where: name.contains) {
                    return true
                }
            }
        }
        return false
    }

    /**
     * Method 4: Kiểm tra URL Scheme của Cydia
     */
    private func checkJailbreakMethod4() -> Bool {
        return canOpenCydiaURL()
    }

    /**
     * Method 5: Kiểm tra stat của /Applications
     */
    private func checkJailbreakMethod5() -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: "/Applications")
            return attributes[FileAttributeKey.type] as? FileAttributeType == .typeSymbolicLink
        } catch {
            return false
        }
    }

    /**
     * Kiểm tra symbolic links
     */
    private func checkSymbolicLinks() -> Bool {
        let symbolicLinks = [
            "/Applications",
            "/Library/Ringtones",
            "/Library/Wallpaper",
            "/usr/arm-apple-darwin9",
            "/usr/include",
            "/usr/libexec",
            "/usr/share"
        ]

        return symbolicLinks.contains { path in
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
               let type = attributes[.type] as? FileAttributeType {
                return type == .typeSymbolicLink
            }
            return false
        }
    }

    /**
     * Kiểm tra khả năng fork process bằng dlsym (tránh compile error trên iOS SDK)
     */
    private func checkFork() -> Bool {
        typealias ForkFunc = @convention(c) () -> Int32
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(RTLD_DEFAULT, "fork") else {
            return false
        }
        let forkFunc = unsafeBitCast(pointer, to: ForkFunc.self)
        let result = forkFunc()
        return result >= 0
    }

    /**
     * Kiểm tra system() function bằng dlsym (tránh compile error trên iOS SDK)
     */
    private func checkSystemFunction() -> Bool {
        typealias SystemFunc = @convention(c) (UnsafePointer<CChar>?) -> Int32
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        guard let pointer = dlsym(RTLD_DEFAULT, "system") else {
            return false
        }
        let systemFunc = unsafeBitCast(pointer, to: SystemFunc.self)
        let result = systemFunc("ls")
        return result == 0
    }

    /**
     * Kiểm tra URL scheme của Cydia
     */
    private func canOpenCydiaURL() -> Bool {
        let cydiaURLSchemes = [
            "cydia://",
            "sileo://",
            "zbra://",
            "installer://",
            "filza://"
        ]

        return cydiaURLSchemes.contains { urlString in
            if let url = URL(string: urlString) {
                return UIApplication.shared.canOpenURL(url)
            }
            return false
        }
    }

    /**
     * Kiểm tra các file nghi ngờ
     */
    private func checkSuspiciousFiles() -> Bool {
        let suspiciousFiles = [
            "/bin/bash",
            "/usr/sbin/sshd",
            "/usr/libexec/ssh-keysign",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/var/lib/cydia",
            "/Library/MobileSubstrate/MobileSubstrate.dylib"
        ]

        return suspiciousFiles.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
