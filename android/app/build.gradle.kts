import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// امضای ریلیز — از android/key.properties خوانده می‌شود.
// فایل در .gitignore است، پس هرگز commit نمی‌شود؛ در CI از روی secret ها
// ساخته می‌شود (.github/workflows/release.yml). نبودِ فایل خطا نیست: در آن
// حالت امضای دیباگ به کار می‌رود.
//
// نکته: مقدارها با getProperty() خوانده می‌شوند نه با props["key"] — داخلِ
// بلوکِ android{} عملگرِ [] به ExtensionContainerِ گریدل resolve می‌شود و
// کامپایل نمی‌شود.
// ---------------------------------------------------------------------------
val overxKeyPropertiesFile = rootProject.file("key.properties")
val overxKeyProperties = Properties()
if (overxKeyPropertiesFile.exists()) {
    overxKeyProperties.load(FileInputStream(overxKeyPropertiesFile))
}
val overxHasReleaseSigning = overxKeyPropertiesFile.exists()


android {
    // نام نمایشی برنامه
    namespace = "com.overx.overx"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // امضای ریلیز از android/key.properties خوانده می‌شود (در .gitignore است).
        // اگر آن فایل نباشد، همان کلیدِ دیباگ به کار می‌رود تا `flutter run
        // --release` روی ماشینِ توسعه هم کار کند.
        if (overxHasReleaseSigning) {
            create("release") {
                // rootProject.file() چون key.properties و keystore هر دو در
                // android/ (ریشه‌ی پروژه) هستند، نه در android/app/.
                storeFile = rootProject.file(overxKeyProperties.getProperty("storeFile"))
                storePassword = overxKeyProperties.getProperty("storePassword")
                keyAlias = overxKeyProperties.getProperty("keyAlias")
                keyPassword = overxKeyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.overx.overx"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // VpnService از API 14 در دسترس است؛ ۲۴ نقطه‌ی شروع امنی است
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // اگر android/key.properties باشد با کلیدِ ریلیزِ خودتان امضا
            // می‌شود (لازم برای انتشار در Play Store)؛ وگرنه با کلیدِ دیباگ،
            // تا `flutter run --release` روی ماشینِ توسعه هم کار کند.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    // ---------------------------------------------------------------- libbox
    // خروجیِ `make lib_android` در مخزن sing-box (یک AAR).
    // اگر وجود نداشته باشد، برنامه کامپایل نمی‌شود — scripts/build_libbox.sh
    // آن را تولید می‌کند.
    val libboxAar = file("../libs/libbox.aar")
    if (libboxAar.exists()) {
        implementation(files(libboxAar))
    } else {
        logger.warn(
            "libbox.aar not found at ${'$'}{libboxAar.path}. " +
                "Run scripts/build_libbox.sh — sing-box will fall back to the CLI path."
        )
    }

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
