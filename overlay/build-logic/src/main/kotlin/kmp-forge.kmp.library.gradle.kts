import org.gradle.api.tasks.testing.AbstractTestTask
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.targets.js.ir.KotlinJsIrTarget

/*
 * Convention applied to every shared KMP library module (:ui, :domain, :data, :feature-*).
 *
 * Implemented as a PRECOMPILED SCRIPT PLUGIN (not a Kotlin class plugin) on purpose:
 * Gradle's kotlin-dsl compiles build-logic with the Kotlin version embedded in Gradle
 * (Kotlin 2.2.x in Gradle 9.x), which cannot read the newer metadata of the Kotlin
 * Gradle plugin the project uses (2.4.x). A class plugin that references KGP types
 * (KotlinMultiplatformExtension, …) therefore fails to compile. A precompiled script
 * plugin uses generated type-safe accessors — the same mechanism that lets an ordinary
 * build.gradle.kts configure `kotlin { }` against a newer KGP — so it compiles cleanly.
 *
 * The Android target is intentionally NOT configured here. Under AGP 9 it comes from the
 * `com.android.kotlin.multiplatform.library` plugin + a `kotlin { android { } }` block, whose
 * namespace differs per module — each module applies that plugin and declares the block.
 *
 * Project property `kmpForge.targets` overrides the non-Android target set, comma-separated,
 * e.g. "iosArm64,iosSimulatorArm64,jvm,js,wasmJs".
 *
 * The ROOT build.gradle.kts applies `id("kmp-forge.root")` (init/adopt add it): that loads
 * build-logic — and the Spotless/Detekt/Kover plugins bundled here — once, in the root
 * classloader (otherwise Spotless 8's shared build service fails configuration), and owns the
 * aggregated Kover gate. See kmp-forge.root.gradle.kts.
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
    if ("wasmJs" in kmpTargets) {
        @OptIn(org.jetbrains.kotlin.gradle.ExperimentalWasmDsl::class)
        wasmJs { browser() }
    }

    // Compose UI on js/wasmJs: the module's tests load Skiko from a webpack bundle, which only
    // exists when the target declares an executable binary (Compose's
    // checkComposeUiTestConfigurationFor<Target> fails the build otherwise). Non-Compose modules
    // (:domain, :data, :testing) stay plain libraries.
    pluginManager.withPlugin("org.jetbrains.compose") {
        targets.withType<KotlinJsIrTarget>().configureEach { binaries.executable() }
    }

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

// ktlint version comes from the catalog's `ktlint` key, so /kmp-forge-bump-stack bumps it
// (type-safe `libs` accessors aren't generated inside precompiled script plugins).
val ktlintVersion = extensions.getByType<VersionCatalogsExtension>()
    .named("libs")
    .findVersion("ktlint")
    .get()
    .requiredVersion

spotless {
    kotlin {
        target("src/**/*.kt")
        ktlint(ktlintVersion)
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint(ktlintVersion)
    }
}
