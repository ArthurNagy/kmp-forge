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

// Convention plugins are PRECOMPILED SCRIPT PLUGINS in src/main/kotlin/*.gradle.kts —
// the `kotlin-dsl` plugin discovers and registers them by filename (e.g.
// kmp-forge.kmp.library.gradle.kts -> id "kmp-forge.kmp.library"). No manual
// gradlePlugin {} registration needed.
