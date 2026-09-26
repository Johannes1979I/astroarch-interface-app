plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zarletti.osservatorio.astroarch_interface"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // v0.2.44: richiesto da flutter_local_notifications (usa java.time)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zarletti.osservatorio.astroarch_interface"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Firma di release con una chiave STABILE.
    //
    // Perche' esiste: firmando con la chiave di debug, Gradle ne genera una
    // nuova su ogni macchina che non ne ha gia' una — e i runner di CI sono
    // effimeri, quindi ogni build produceva una firma diversa. Android
    // rifiuta di installare un APK sopra uno firmato diversamente, cosi'
    // ogni aggiornamento costringeva a disinstallare, perdendo bridge
    // salvate e token. Misurato: v0.3.0 SHA1 7D:8D:2A:80..., v0.4.0
    // 8E:93:52:01..., entrambi costruiti dalla stessa CI.
    //
    // Il keystore non sta nel repo: la CI lo scrive da un segreto e passa
    // il percorso in ANDROID_KEYSTORE_PATH. Se quella variabile non c'e'
    // (build locale, `flutter run --release`) si ricade sulla chiave di
    // debug come prima, cosi' nessuno resta bloccato senza i segreti.
    signingConfigs {
        create("release") {
            val ksPath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (ksPath != null) {
                storeFile = file(ksPath)
                storeType = "PKCS12"
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("ANDROID_KEYSTORE_PATH") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // v0.2.44: core library desugaring per flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
