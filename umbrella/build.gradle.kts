plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.kotlinCocoapods)
    alias(libs.plugins.composeMultiplatform)
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.composeCompiler)
}

kotlin {
    androidTarget()
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    cocoapods {
        version = "1.0.0"
        name = "Umbrella"

        summary = "Umbrella framework aggregating shared KMP modules"
        homepage = "https://github.com/Adnan-Isnain/showcase-mobile-app"
        ios.deploymentTarget = "15.1"
        framework {
            baseName = "Umbrella"
            isStatic = true
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(compose.runtime)
            }
        }
        val androidMain by getting
    }
}

android {
    namespace = "com.adnanisnain.showcase.umbrella"
    compileSdk = libs.versions.android.compileSdk.get().toInt()
    defaultConfig { minSdk = libs.versions.android.minSdk.get().toInt() }
}
