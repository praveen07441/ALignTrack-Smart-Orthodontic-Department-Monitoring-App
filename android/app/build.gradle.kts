plugins {
    id("com.android.application")
    id("com.google.gms.google-services")   // 🔥 Firebase plugin
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ✅ FIXED: Must match Firebase + iOS
    namespace = "com.praveen.clinicalmonitor"

    compileSdk = 36

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // ✅ FIXED: Must match Firebase
        applicationId = "com.praveen.clinicalmonitor"

        minSdk = flutter.minSdkVersion
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

    buildTypes {
        release {
            // ⚠️ Use proper signing later for Play Store
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 🔥 Required for Java 17 support
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // 🔥 Firebase BOM (manages versions automatically)
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))

    // 🔥 Firebase services
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-messaging")
}