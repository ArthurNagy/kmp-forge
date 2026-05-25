# Observability

## Tiered approach

**Default**: platform out-of-box crash reporting. Zero infra.
**Opt-in**: Sentry across all platforms. Single SDK + dashboard. Adds breadcrumbs, real-time alerts, desktop/web coverage.

Analytics and performance monitoring are **opt-in per project** — not part of v1 defaults.

## v1 default: platform out-of-box

### Android — Google Play Console > Android Vitals

Captures **automatically** for users installed via Play Store with Play Services:
- Crash rate (unhandled exceptions)
- ANR rate
- Excessive wakeups, frozen frames, slow rendering

**Read at**: Play Console → App → Quality → Android Vitals.

**Limits**:
- Only Play-Store-installed users
- No real-time alerts (hourly batch)
- No breadcrumbs / log context attached to crashes
- Sideload or Firebase App Distribution users → not captured here
- Internal testing track is partially covered

### iOS — Xcode Organizer + App Store Connect

Captures **automatically** for TestFlight and App Store builds when users have "Share With App Developers" enabled (default on iOS 12+):
- Crash reports (symbolicated)
- Hang rate (app unresponsive)
- Disk write rate

**Read at**: Xcode → Window → Organizer → Crashes, or App Store Connect → Apps → <App> → TestFlight/App Store → Metrics.

**Limits**:
- Only TestFlight or App Store builds (dev builds not captured)
- Hours-to-days delay
- No breadcrumbs
- Opt-out by user disables it

### When out-of-box is enough

- Solo dev, store-only distribution
- OK to wait hours for crash data
- Don't need breadcrumbs or log context
- No desktop or web target

If any of those is false, opt into Sentry.

## Opt-in: Sentry

Single SDK across Android, iOS, desktop (JVM), web (JS, wasm-js).

### Setup

`gradle/libs.versions.toml`:
```toml
sentry = "8.x.x"
sentryKotlinMultiplatform = "0.x.x"
```

`composeApp/build.gradle.kts` (add to common dependencies):
```kotlin
sourceSets.commonMain.dependencies {
    implementation("io.sentry:sentry-kotlin-multiplatform:${libs.versions.sentryKotlinMultiplatform.get()}")
}
```

`composeApp/src/commonMain/kotlin/App.kt` (or platform entry points):
```kotlin
Sentry.init { options ->
    options.dsn = AppBuildConfig.sentryDsn
    options.environment = if (AppBuildConfig.isDebug) "debug" else "release"
    options.tracesSampleRate = 0.1   // optional, off by default
    options.attachStacktrace = true
}
```

Init **before** Koin starts and **before** any Composable renders.

### Kermit → Sentry sink

Logs at `ERROR` or `WARN` severity become Sentry breadcrumbs and attach to subsequent crash reports.

```kotlin
Logger.setLogWriters(
    platformLogWriter(),                              // local logcat / NSLog / println
    SentryLogWriter(minSeverity = Severity.Warn),     // breadcrumbs
)
```

Crashes get the last ~50 log entries as breadcrumb context. Game-changing for debugging.

### Source-map / symbol upload

CI uploads dSYMs (iOS) and mapping files (Android R8/Proguard) via Sentry CLI:

```yaml
- uses: getsentry/action-release@v1
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: <your-org>
    SENTRY_PROJECT: <your-project>
  with:
    environment: production
    sourcemaps: composeApp/build/outputs/mapping/release/
```

For iOS dSYMs: `sentry-cli upload-dif <path-to-dsyms>` in release workflow.

### Release tagging

Tie Sentry releases to git tags:

```kotlin
Sentry.init { options ->
    options.release = AppBuildConfig.versionName
}
```

CI's `getsentry/action-release` reads the git tag automatically.

## Analytics (opt-in, per project)

Not in v1 defaults. Common options when a project needs it:

- **PostHog** (`com.posthog:posthog-kmp`) — KMP SDK, event analytics + feature flags + session replay, generous free tier, self-host option.
- **Firebase Analytics** — Android/iOS only, free, integrates with Crashlytics. No first-class KMP common API; wrap per-platform.

Add via per-project decision documented in `docs/DECISIONS/NNNN-analytics.md`.

## Performance monitoring (opt-in, per project)

Not in v1 defaults. Common options:

- **Sentry Performance** — already bundled with Sentry SDK if opted in. Set `tracesSampleRate` > 0.
- **Firebase Performance Monitoring** — Android/iOS only, free, automatic HTTP + screen rendering traces.

## What to log

- **Info**: user-initiated actions worth seeing in breadcrumbs ("opened photo:123")
- **Warn**: recoverable errors, retries, fallback paths
- **Error**: unhandled errors caught at ViewModel boundary, network 5xx, db failures

Avoid logging at `Debug`/`Verbose` outside dev builds — Kermit's `minSeverity` config in production silences them.

## Privacy

Never log PII. Strip user IDs, emails, location, photos, free-text input from log messages. Use stable hashed IDs when you need correlation across logs.
