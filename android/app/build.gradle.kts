import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties, which is git-ignored.
// Without it (a fresh checkout, CI) the build still runs and falls back to the
// debug key, so `flutter build apk` never fails just because a keystore is
// missing.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.haramblur.haram_blur"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.haramblur.haram_blur"
        minSdk = 30
        // Compile and target the current SDK: apps below 35 run in a
        // compatibility mode on Android 15+ and Play stops accepting them.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("en")
        // ABI selection is done on the flutter build command
        // (--target-platform android-arm,android-arm64 and/or
        // --split-per-abi) so the emulator libraries are not shipped.
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // key.properties paths are relative to android/, not to app/.
                storeFile = rootProject.file(
                    keystoreProperties["storeFile"] as String,
                )
                storePassword = keystoreProperties["storePassword"] as String
                // REA showed the shipped APK declaring only v2. v3 is what
                // carries a key-rotation lineage, so an app signed v2-only can
                // never rotate its signing key; v1 is pointless at minSdk 30.
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = false
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 with resource shrinking: the release APK ships only the
            // classes, models and strings it actually reaches.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // TensorFlow Lite runtime for on-device NSFW classification.
    //
    // NOTE: the flutter_litert plugin already contributes
    // com.google.ai.edge.litert:litert:1.4.2, whose AAR ships the very same
    // org/tensorflow/lite/* classes and libtensorflowlite_jni.so as
    // org.tensorflow:tensorflow-lite. Declaring tensorflow-lite here as well
    // makes D8 fail with "Duplicate class org.tensorflow.lite.Interpreter", and
    // tensorflow-lite-support:0.4.4 pulls tensorflow-lite:2.13.0 back in, which
    // triggers the same conflict. We therefore compile against the LiteRT
    // artifacts that are already on the classpath.
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    implementation("com.google.ai.edge.litert:litert-api:1.4.2")
    // FileProvider for handing the camera app a private output file.
    implementation("androidx.core:core-ktx:1.13.1")
    // Face detection runs on MediaPipe's BlazeFace short-range model
    // (Apache-2.0, bundled in src/main/assets/models) through LiteRT, so the
    // app carries no proprietary ML Kit blobs and can be built by F-Droid.
    // JVM-only tests for pure geometry (no Android framework stubs needed).
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
