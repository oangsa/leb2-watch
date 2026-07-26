import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
val hasReleaseSigningConfiguration = releaseSigningPropertiesFile.exists()

if (hasReleaseSigningConfiguration) {
    FileInputStream(releaseSigningPropertiesFile).use { input ->
        releaseSigningProperties.load(input)
    }
    val requiredSigningProperties =
        listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
    require(
        requiredSigningProperties.all { name ->
            !releaseSigningProperties.getProperty(name).isNullOrBlank()
        },
    ) {
        "android/key.properties must define nonblank storePassword, " +
            "keyPassword, keyAlias, and storeFile values."
    }
} else {
    logger.warn(
        "Android release signing is not configured. Release output will be " +
            "unsigned and is not distributable.",
    )
}

android {
    namespace = "dev.oangsa.leb2watch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.oangsa.leb2watch"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigningConfiguration) {
            create("release") {
                storeFile = file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigningConfiguration) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
