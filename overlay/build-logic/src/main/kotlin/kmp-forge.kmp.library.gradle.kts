import org.gradle.api.tasks.testing.AbstractTestTask
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

/*
 * Convention applied to every shared KMP library module (:ui, :domain, :data, :feature-*).
 *
 * Implemented as a PRECOMPILED SCRIPT PLUGIN (not a Kotlin class plugin) on purpose:
 * Gradle's kotlin-dsl compiles build-logic with the Kotlin version embedded in Gradle
 * (Kotlin 2.2.0 in Gradle 9.1), which cannot read the newer metadata of the Kotlin
 * Gradle plugin the project uses (2.4.x). A class plugin that references KGP types
 * (KotlinMultiplatformExtension, …) therefore fails to compile. A precompiled script
 * plugin uses generated type-safe accessors — the same mechanism that lets an ordinary
 * build.gradle.kts configure `kotlin { }` against a newer KGP — so it compiles cleanly.
 *
 * The Android target is intentionally NOT configured here. Under AGP 9 it comes from the
 * `com.android.kotlin.multiplatform.library` plugin + an `androidLibrary { }` block, whose
 * namespace differs per module — each module applies that plugin and declares the block.
 *
 * Project property `kmpForge.targets` overrides the non-Android target set, comma-separated,
 * e.g. "iosArm64,iosSimulatorArm64,jvm,js,wasmJs".
 */

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("io.gitlab.arturbosch.detekt")
    id("com.diffplug.spotless")
    id("org.jetbrains.kotlinx.kover")
}

val kmpTargets = providers.gradleProperty("kmpForge.targets")
    .orElse("iosArm64,iosSimulatorArm64,jvm")
    .get()
    .split(",")
    .map(String::trim)

kotlin {
    if ("jvm" in kmpTargets) {
        jvm {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
    if ("iosArm64" in kmpTargets) iosArm64()
    if ("iosSimulatorArm64" in kmpTargets) iosSimulatorArm64()
    if ("iosX64" in kmpTargets) iosX64()
    if ("js" in kmpTargets) js { browser() }
    if ("wasmJs" in kmpTargets) wasmJs { browser() }

    sourceSets.configureEach {
        languageSettings {
            languageVersion = "2.4"
            apiVersion = "2.4"
            progressiveMode = true
        }
    }
}

// Detekt: the default source set is JVM-style (src/main) and finds nothing in a KMP module,
// leaving the gate vacuous. Point it at the whole `src` tree (commonMain + platform source sets)
// and at the project's detekt.yml so static analysis actually runs.
detekt {
    source.setFrom("src")
    config.setFrom(rootProject.file("detekt.yml"))
    buildUponDefaultConfig = true
}

// Gradle 9 fails a test task that has test SOURCE but discovers no @Test. kmp-forge's
// commonTest ships test utilities (e.g. TestDispatcherProvider) before any feature adds
// real tests, so don't fail an otherwise-green build on "no tests discovered".
tasks.withType<AbstractTestTask>().configureEach {
    failOnNoDiscoveredTests = false
}

spotless {
    kotlin {
        target("src/**/*.kt")
        ktlint("1.5.0")
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint("1.5.0")
    }
}
