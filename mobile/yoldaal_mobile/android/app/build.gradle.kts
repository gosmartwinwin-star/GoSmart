import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

val releaseKeystorePropertiesFile = rootProject.file("key.properties")
val releaseKeystoreProperties = Properties()

if (releaseKeystorePropertiesFile.isFile) {
    releaseKeystorePropertiesFile.inputStream().use {
        releaseKeystoreProperties.load(it)
    }
}

fun releaseSigningProperty(name: String): String? =
    releaseKeystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val releaseStoreFilePath = releaseSigningProperty("storeFile")
val releaseStorePassword = releaseSigningProperty("storePassword")
val releaseKeyAlias = releaseSigningProperty("keyAlias")
val releaseKeyPassword = releaseSigningProperty("keyPassword")
val releaseStoreFile = releaseStoreFilePath?.let { file(it) }

if (releaseBuildRequested) {
    if (!releaseKeystorePropertiesFile.isFile) {
        throw org.gradle.api.GradleException(
            "Android release signing requires android/key.properties. Debug signing fallback is disabled.",
        )
    }

    val missingProperties =
        listOf(
            "storeFile" to releaseStoreFilePath,
            "storePassword" to releaseStorePassword,
            "keyAlias" to releaseKeyAlias,
            "keyPassword" to releaseKeyPassword,
        ).filter { it.second == null }.map { it.first }

    if (missingProperties.isNotEmpty()) {
        throw org.gradle.api.GradleException(
            "Android release signing is missing required key.properties entries: ${missingProperties.joinToString(", ")}",
        )
    }

    if (releaseStoreFile == null || !releaseStoreFile.isFile) {
        throw org.gradle.api.GradleException(
            "Android release signing storeFile does not exist.",
        )
    }
}

val releaseSigningMaterialAvailable =
    releaseKeystorePropertiesFile.isFile &&
    releaseStoreFilePath != null &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null &&
    releaseStoreFile?.isFile == true

android {
    namespace = "com.yoldaal.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.yoldaal.app"

        // Google Maps için güvenli değer
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningMaterialAvailable) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningMaterialAvailable) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
