plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: replace with a real release keystore before publishing.
            // Debug signing keeps `flutter build apk --release` working locally.
            signingConfig = signingConfigs.getByName("debug")
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
