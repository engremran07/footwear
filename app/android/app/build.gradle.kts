import java.util.Properties
import com.android.build.api.dsl.ApplicationExtension

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

fun computeAndroidVersionCode(buildNumber: Int): Int {
    if (buildNumber <= 0) {
        throw GradleException("The Flutter build number must be a positive sequence.")
    }

    // Keep in sync with AppBrand.androidVersionCodeBase; anchored to Play code 310191130.
    val versionCode = 310_190_000L + buildNumber.toLong()
    if (versionCode > 2_100_000_000L) {
        throw GradleException("Android versionCode exceeds the Play Console limit.")
    }
    return versionCode.toInt()
}

val buildingAppBundle = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true)
}

extensions.configure<ApplicationExtension> {
    namespace = "footwear.com.pk"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "footwear.com.pk"
        minSdk = 29
        targetSdk = 36
        versionCode = computeAndroidVersionCode(flutter.versionCode)
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
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget("17")
    }
}

tasks.configureEach {
    val isReleasePackagingTask =
        name.contains("Release", ignoreCase = true) &&
            (name.startsWith("assemble", ignoreCase = true) ||
                name.startsWith("bundle", ignoreCase = true) ||
                name.startsWith("package", ignoreCase = true))
    if (isReleasePackagingTask) {
        doFirst {
            if (!keystorePropertiesFile.isFile) {
                throw GradleException(
                    "key.properties not found at ${keystorePropertiesFile.absolutePath}. " +
                        "Release builds require a valid signing configuration."
                )
            }
            val requiredSigningProperties =
                listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
            val missingSigningProperties = requiredSigningProperties.filter {
                keystoreProperties.getProperty(it).isNullOrBlank()
            }
            if (missingSigningProperties.isNotEmpty()) {
                throw GradleException(
                    "Release signing configuration is incomplete; missing: " +
                        missingSigningProperties.joinToString()
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
