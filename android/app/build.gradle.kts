import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// google-services.json в git нет (CI кладёт его из секрета). Без файла сборка
// не падает, просто пуши в ней не работают — приложение это переживает.
googleServices {
    missingGoogleServicesStrategy =
        com.google.gms.googleservices.GoogleServicesPlugin.MissingGoogleServicesStrategy.WARN
}

// Ключ для release-подписи. Без него каждая пересборка получает новый
// debug-ключ, и Android отказывается ставить обновление поверх старой
// версии — требует сначала удалить приложение. Файл в .gitignore.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val arm64Only = System.getenv("ARM64_ONLY") == "1" ||
    (project.findProperty("arm64Only") as String?) == "true"

android {
    namespace = "ru.socialworld.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Требование flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.socialworld.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Yandex MapKit Android SDK requires API 26+, keep Flutter's floor if it rises later.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ARM64_ONLY=1 задаёт CI для тестовой сборки и лёгкого файла обновления.
        // `flutter build --target-platform android-arm64` режет только движок
        // Flutter, а нативные библиотеки Яндекс-карт всё равно приезжают для
        // всех трёх архитектур: APK выходил 139 МБ вместо ~74 (лишние
        // armeabi-v7a и x86_64 ≈ 65 МБ, которые arm64-телефону не нужны).
        // Универсальный APK для остальных телефонов собирается без флага.
        // 07.10: одного ndk.abiFilters мало — в «arm64»-файле 5151 всё равно
        // лежали x86_64 и armeabi-v7a (180 МБ). Теперь флаг приходит и
        // параметром Gradle (-Parm64Only=true из CI), а лишние папки
        // вырезаются при упаковке (packaging ниже).
        if (arm64Only) {
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    packaging {
        jniLibs {
            // x86_64 нужен только эмуляторам: телефоны пользователей на ARM.
            excludes += listOf("lib/x86_64/**", "lib/x86/**")
            if (arm64Only) excludes += listOf("lib/armeabi-v7a/**")
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Если key.properties нет (например, на чужой машине), собираемся
            // debug-ключом, чтобы `flutter run --release` не падал — но такую
            // сборку нельзя выкладывать как обновление в сторе или на устройства
            // с уже установленным релизом.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
