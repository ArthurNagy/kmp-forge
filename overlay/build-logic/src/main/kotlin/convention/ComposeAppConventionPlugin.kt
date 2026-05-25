package convention

import org.gradle.api.Plugin
import org.gradle.api.Project

/**
 * Convention plugin for the :composeApp module.
 * Applies Compose Multiplatform on top of the KMP library conventions.
 */
class ComposeAppConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("kmp-forge.kmp.library")
            pluginManager.apply("org.jetbrains.compose")
            pluginManager.apply("org.jetbrains.kotlin.plugin.compose")
        }
    }
}
