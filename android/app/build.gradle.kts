import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 应用内更新的前提：所有分发出去的 APK 必须用同一把密钥签名，否则覆盖安装会被系统
// 以 INSTALL_FAILED_UPDATE_INCOMPATIBLE 拒绝（CI runner 上的临时 debug keystore
// 每次构建都不一样，曾导致 2.4.0 → 2.5.0 装不上）。
// 密钥来自 GitHub Secrets，构建前还原成 android/app/wof-release.jks 并写
// android/key.properties；两者都在 android/.gitignore 里。本地缺 key.properties
// 时退回 debug 签名，保证 `flutter build apk` 照样能跑。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties =
    Properties().apply {
        if (hasReleaseKeystore) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }

android {
    namespace = "com.wof.nai_launcher"
    compileSdk = flutter.compileSdkVersion

    // Pin the NDK to a locally installed version. super_native_extensions
    // (super_clipboard / super_drag_and_drop) requires an NDK at build time.
    // Keep this aligned with the NDK installed in the Android SDK; otherwise
    // Gradle would try to download a ~1 GB NDK during the build.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.wof.nai_launcher"
        // super_native_extensions requires minSdk 23; 24 matches the oldest
        // Android release still worth supporting for a 2026 desktop-class app.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有固定密钥就用它，缺省回退 debug 签名（本地临时构建）。
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    packaging {
        jniLibs {
            // sqlite3_flutter_libs / super_native_extensions ship .so files that
            // are loaded from the extracted native library directory.
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}
