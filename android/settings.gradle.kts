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

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("/workspace/local-maven-repo") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
