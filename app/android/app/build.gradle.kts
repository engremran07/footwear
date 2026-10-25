import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun computeAndroidVersionCode(versionName: String, buildNumber: Int): Int {
    val parts = versionName.split(".")
    val major = parts.getOrNull(0)?.toIntOrNull() ?: 0
    val minor = parts.getOrNull(1)?.toIntOrNull() ?: 0
    val patch = parts.getOrNull(2)?.toIntOrNull() ?: 0
    if (major < 1 || minor !in 0..99 || patch !in 0..99 || buildNumber !in 0..9_999) {
        throw GradleException(
            "Version components exceed the Android versionCode encoding limits."
        )
    }
    val versionCode =
        major.toLong() * 100_000_000L +
        minor.toLong() * 1_000_000L +
        patch.toLong() * 10_000L +
        buildNumber.toLong()
    if (versionCode > 2_100_000_000L) {
        throw GradleException("Android versionCode exceeds the Play Console limit.")
    }
    return versionCode.toInt()
}

val buildingAppBundle = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true)
}

android {
    namespace = "footwear.pk.com"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "footwear.pk.com"
        minSdk = 29
        targetSdk = 36
        versionCode = computeAndroidVersionCode(flutter.versionName, flutter.versionCode)
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"].toString()
                keyPassword = keystoreProperties["keyPassword"].toString()
                storeFile = file(keystoreProperties["storeFile"].toString())
                storePassword = keystoreProperties["storePassword"].toString()
            }
        }
    }

    splits {
        abi {
            isEnable = !buildingAppBundle
            isUniversalApk = !buildingAppBundle
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "key.properties not found at ${keystorePropertiesFile.absolutePath}. " +
                    "Release builds require a valid signing configuration."
                )
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
