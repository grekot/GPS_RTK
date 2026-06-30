plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.gpsrtk.gps_rtk_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pl.gpsrtk.gps_rtk_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Stały, commitowany debug-keystore — żeby APK budowane w CI i na maszynie
        // dev miały TEN SAM podpis. Bez tego każdy runner CI generuje losowy
        // ~/.android/debug.keystore → inny podpis co build → aktualizacja „w miejscu"
        // pada z „App not installed — package conflicts with an existing package".
        // To standardowy klucz debug Androida (hasła android/android), więc bezpieczny
        // do commitu; NIE jest to klucz produkcyjny.
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // Podpis kluczem debug (stały, jak wyżej), by `flutter run --release` działał.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
