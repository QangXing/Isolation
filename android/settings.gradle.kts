pluginManagement {
    val flutterSdkPath =
        run {
            val localProperties = file("local.properties")
            if (localProperties.exists()) {
                val properties = java.util.Properties()
                localProperties.inputStream().use { properties.load(it) }
                properties.getProperty("flutter.sdk")
            } else {
                null
            }
        } ?: System.getenv("FLUTTER_ROOT") ?: System.getenv("FLUTTER_HOME")
    require(!flutterSdkPath.isNullOrEmpty()) {
        "Flutter SDK not found. Set flutter.sdk in android/local.properties or FLUTTER_ROOT/FLUTTER_HOME environment variable."
    }

    includeBuild("/workspace/flutter_tools_gradle")

    repositories {
        maven { url = uri("file:///workspace/local-maven-repo") }
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
