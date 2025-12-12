import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode")
val flutterVersionName = localProperties.getProperty("flutter.versionName")

android {
    namespace = "com.rendeyllc.us_tax_calculator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.rendeyllc.us_tax_calculator"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toIntOrNull() ?: 1
        versionName = flutterVersionName ?: "1.0"
    }

    signingConfigs {
        create("release") {
            // --- ATENÇÃO: COLOQUE SUA SENHA AQUI ---
            // Estamos colocando direto aqui para não depender do arquivo externo que está falhando
            
            // 1. Onde está o arquivo? (Procura na pasta android/app/)
            storeFile = file("upload-keystore.jks")
            
            // 2. Senhas (Troque 'SuaSenhaAqui' pela senha que você criou no terminal)
            storePassword = "@@Renan2025"
            keyAlias = "upload"
            keyPassword = "@@Renan2025"
        }
    }

    buildTypes {
        getByName("release") {
            // Usa a configuração que criamos acima
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}