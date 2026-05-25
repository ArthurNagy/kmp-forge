package convention

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

/**
 * Convention plugin applied to every shared KMP library module (:ui, :domain, :data, :feature-*).
 * Sets the KMP targets matching the project's chosen platforms.
 *
 * Project property `kmpForge.targets` may override the default target set,
 * comma-separated: "android,iosArm64,iosSimulatorArm64,jvm,js,wasmJs"
 */
class KmpLibraryConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("org.jetbrains.kotlin.multiplatform")
            pluginManager.apply("io.gitlab.arturbosch.detekt")
            pluginManager.apply("com.diffplug.spotless")
            pluginManager.apply("org.jetbrains.kotlinx.kover")

            // Spotless wraps ktlint — formats and verifies Kotlin sources.
            // ktlint version pinned in libs.versions.toml; consumers may override.
            extensions.configure(com.diffplug.gradle.spotless.SpotlessExtension::class.java) { spotless ->
                spotless.kotlin { k ->
                    k.target("src/**/*.kt")
                    k.ktlint("1.5.0")
                }
                spotless.kotlinGradle { kg ->
                    kg.target("*.gradle.kts")
                    kg.ktlint("1.5.0")
                }
            }

            extensions.configure(KotlinMultiplatformExtension::class.java) { kmp ->
                val targets = (findProperty("kmpForge.targets") as String?)
                    ?.split(",")
                    ?.map(String::trim)
                    ?: listOf("android", "iosArm64", "iosSimulatorArm64", "jvm")

                targets.forEach { t ->
                    when (t) {
                        "android" -> kmp.androidTarget()
                        "iosArm64" -> kmp.iosArm64()
                        "iosSimulatorArm64" -> kmp.iosSimulatorArm64()
                        "jvm" -> kmp.jvm()
                        "js" -> kmp.js { browser() }
                        "wasmJs" -> kmp.wasmJs { browser() }
                        else -> error("Unknown KMP target: $t")
                    }
                }

                kmp.sourceSets.configureEach {
                    it.languageSettings.apply {
                        languageVersion = "2.2"
                        apiVersion = "2.2"
                        progressiveMode = true
                    }
                }
            }
        }
    }
}
