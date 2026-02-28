pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // ✅ FIX: AGP must be 8.9.1+ because androidx.browser:browser:1.9.0 requires it
    id("com.android.application") version "8.9.1" apply false
    id("com.android.library") version "8.9.1" apply false

    // ✅ Keep Kotlin plugin as you had (works with Flutter warning you mentioned)
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false

    // ✅ Google Services
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")