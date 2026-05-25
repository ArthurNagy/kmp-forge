plugins {
    `kotlin-dsl`
}

dependencies {
    implementation(libs.kotlin.gradle.plugin)
    implementation(libs.android.gradle.plugin)
    implementation(libs.compose.gradle.plugin)
    implementation(libs.compose.compiler.gradle.plugin)
    implementation(libs.detekt.gradle.plugin)
    implementation(libs.spotless.gradle.plugin)
    implementation(libs.kover.gradle.plugin)
}

gradlePlugin {
    plugins {
        register("kmpLibrary") {
            id = "kmp-forge.kmp.library"
            implementationClass = "convention.KmpLibraryConventionPlugin"
        }
        register("composeApp") {
            id = "kmp-forge.compose.app"
            implementationClass = "convention.ComposeAppConventionPlugin"
        }
    }
}
