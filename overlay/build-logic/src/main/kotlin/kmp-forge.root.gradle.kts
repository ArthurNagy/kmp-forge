/*
 * Convention for the ROOT project — applied as `id("kmp-forge.root")` in the root
 * build.gradle.kts (init/adopt add it).
 *
 * 1. Loads build-logic — and the Spotless/Detekt/Kover plugins it bundles — once, in the root
 *    classloader. Without that every module loads its own copy and Spotless 8's shared build
 *    service fails configuration ("Cannot set the value of task ':x:spotlessKotlin' property
 *    'taskService' ... loaded with ... project-y").
 * 2. Owns the coverage gate: aggregates Kover data from every module that applies
 *    `kmp-forge.kmp.library` (except :testing, which only holds test doubles) and fails
 *    `./gradlew koverVerify` below 75% line coverage. New :feature-* modules are picked up
 *    automatically — nothing to register.
 */

plugins {
    id("org.jetbrains.kotlinx.kover")
}

subprojects {
    if (name != "testing") {
        pluginManager.withPlugin("kmp-forge.kmp.library") {
            rootProject.dependencies.add("kover", this@subprojects)
        }
    }
}

kover {
    reports {
        filters {
            excludes {
                // UI is covered by Compose UI / screenshot tests, not line coverage.
                annotatedBy("androidx.compose.runtime.Composable")
                classes(
                    // generated code: Compose resources (default package, the features' pinned
                    // `<base>.feature.<pkg>.resources` and :ui's `<base>.ui.resources`), Compose
                    // singletons, serializers
                    "*.generated.resources.*",
                    "*.feature.*.resources.*",
                    "*.ui.resources.*",
                    "*ComposableSingletons*",
                    "*\$\$serializer",
                    // wiring: Koin module declarations (fooModule.kt → FooModuleKt, and per-platform
                    // actuals: PlatformDataModule.android.kt → PlatformDataModule_androidKt), Nav 3 entry
                    // contributions (FooNavEntry.kt → FooNavEntryKt) and feature routes (NavKeys, plus a
                    // data-class route's generated Companion)
                    "*ModuleKt",
                    "*Module_*Kt",
                    "*NavEntryKt",
                    "*.feature.*Route",
                    "*.feature.*Route\$Companion",
                    // the DomainError value types (cases carry no logic; they are exercised wherever
                    // the code that returns them is tested)
                    "*.domain.DomainError*",
                    // platform wiring (per-target dispatcher one-liners, the opt-in Ktor client
                    // factory — data sources are tested against Ktor's MockEngine, platform `actual`
                    // adapters kept in `<base>.data.platform` — SharedPreferences / NSUserDefaults
                    // stores, DataStore and SQLDelight driver factories) and :ui tokens
                    "*.RealDispatcherProvider*",
                    "*.data.platform.*",
                    "*.data.HttpClientFactoryKt",
                    "*.ui.AppColorsKt",
                    "*.ui.AppDimens",
                    "*.ui.AppSpacing",
                    "*.ui.AppType",
                    "*.ui.ThemeMode",
                )
            }
        }
        verify {
            rule("Aggregated line coverage") {
                minBound(75)
            }
        }
    }
}
