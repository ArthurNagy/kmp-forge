# Testing

## Layout

```
:domain/src/commonTest/         use case tests
:data/src/commonTest/           repository tests with FakeXxxDataSource
:data/src/jvmTest/              optional: MockK for third-party platform deps
:feature-*/src/commonTest/      ViewModel tests with Orbit's test() harness
:ui/src/commonTest/             optional: Composable behavior tests
:testing/src/commonMain/        shared test doubles — TestDispatcherProvider, fakes used by >1 module
```

`:testing` holds test code in `commonMain` (KMP has no `testFixtures`) so every module's `commonTest` can depend on it: `commonTest.dependencies { implementation(project(":testing")) }` (the overlay's `:domain`, `:data` and `:feature-*` templates already do). It is never a `commonMain` dependency and is excluded from the Kover report. Module-local fakes stay in that module's `commonTest`.

## Frameworks

- **Assertions**: `kotlin.test` stdlib in `commonTest`. No Kotest unless a specific feature needs DSL/property tests.
- **MVI tests**: Orbit's `test()` harness (`orbit-test`) for happy-path state transitions.
- **Flow / edge cases**: Turbine on `stateFlow`/`container.stateFlow`.
- **UI behavior**: `runComposeUiTest {}` in `commonTest`.
- **No screenshot tests in v1**. Add Roborazzi/Paparazzi per-project when visual regressions matter.

## Fakes-first policy

Default: write hand-rolled `Fake<Name>` implementations of every interface in `commonTest`. Fakes encode realistic stateful behavior (in-memory store, predictable responses).

```kotlin
import com.github.michaelbull.result.Ok
import com.github.michaelbull.result.Err
import com.github.michaelbull.result.Result

class FakeUserRepository : UserRepository {
    private val users = mutableMapOf<UserId, User>()
    var nextError: DomainError? = null

    override suspend fun getUser(id: UserId): Result<User, DomainError> =
        nextError?.let { Err(it) }
            ?: users[id]?.let { Ok(it) }
            ?: Err(UserError.NotFound)

    fun seed(user: User) { users[user.id] = user }
}
```

`Result`/`Ok`/`Err` are [kotlin-result](https://github.com/michaelbull/kotlin-result) (package `com.github.michaelbull.result`), not `kotlin.Result`. `UserError.NotFound` is a `sealed interface UserError : DomainError` case.

## When MockK is allowed

MockK is JVM-only and **cannot** appear in `commonTest`. It is allowed in `jvmTest` or `androidTest` for **platform/third-party dependencies whose interfaces you do not own** — e.g. a complex Ktor engine response, an Android `Context`, an iOS `NSURLSession`.

Rules:
- Never mock an interface you authored — write a fake.
- Never mock domain types — fakes give better signal.
- Document the reason in a single-line comment above the mock: `// mocked: third-party Ktor MockEngine API too large to fake faithfully`.

## ViewModel test pattern

```kotlin
class GalleryViewModelTest {

    @Test
    fun loadSetsPhotosOnSuccess() = runTest {
        val repo = FakeUserRepository().apply { seed(samplePhoto) }
        val vm = GalleryViewModel(GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler)))

        // Orbit 12 (`org.orbitmvi.orbit.test.testWithInternalState`): the initial state is
        // asserted automatically; then consume every emitted state in order.
        vm.testWithInternalState(this, GalleryState.Initial) {
            containerHost.load()
            expectInternalState { copy(loading = true) }
            expectInternalState { copy(loading = false, photos = listOf(samplePhoto)) }
        }
    }

    @Test
    fun loadSurfacesErrorOnFailure() = runTest {
        val repo = FakeUserRepository().apply { nextError = DomainError.NetworkUnavailable }
        val vm = GalleryViewModel(GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler)))

        vm.testWithInternalState(this, GalleryState.Initial) {
            containerHost.load()
            expectInternalState { copy(loading = true) }
            expectInternalState { copy(loading = false, error = DomainError.NetworkUnavailable) }
        }
    }
}
```

## Turbine for edge cases

When you need to assert non-trivial Flow timing (debounce, throttle, multi-source merge), drop into Turbine on `container.stateFlow`:

```kotlin
vm.container.stateFlow.test {
    awaitItem() // initial state
    vm.search("foo")
    awaitItem().query shouldBe "foo"
    expectNoEvents() // debounce window
    advanceTimeBy(300)
    awaitItem().results shouldHaveSize 3
}
```

## DispatcherProvider in tests

Every use case takes a `DispatcherProvider`. In tests, use `:testing`'s `TestDispatcherProvider`, **always constructed with the `runTest` scheduler**:

```kotlin
// :testing/src/commonMain/kotlin/<base>/testing/TestDispatcherProvider.kt (shipped by the overlay)
class TestDispatcherProvider(scheduler: TestCoroutineScheduler) : DispatcherProvider {
    private val dispatcher = StandardTestDispatcher(scheduler)
    override val main: CoroutineDispatcher get() = dispatcher
    override val io: CoroutineDispatcher get() = dispatcher
    override val default: CoroutineDispatcher get() = dispatcher
}

@Test
fun loadsPhotos() = runTest {
    val useCase = GetPhotosUseCase(FakePhotoRepository(), TestDispatcherProvider(testScheduler))
    // delays inside the use case run on runTest's virtual clock
}
```

Why the scheduler parameter: a `StandardTestDispatcher()` created on its own gets its **own** scheduler, which `runTest` can't advance — tests fail with "Detected use of different schedulers" or hang. Sharing `testScheduler` keeps one virtual clock.

## Compose UI Test

For behavior tests on Composables (not screenshots):

```kotlin
class GalleryScreenTest {
    @Test
    fun `tapping photo emits open intent`() = runComposeUiTest {
        var openedId: PhotoId? = null
        setContent {
            AppTheme {
                GalleryScreen(state = GalleryState(photos = listOf(samplePhoto)), onOpen = { openedId = it })
            }
        }
        onNodeWithTag("photo:${samplePhoto.id.value}").performClick()
        assertEquals(samplePhoto.id, openedId)
    }
}
```

- Use `testTag` on tap targets.
- Composables under test must be stateless (state hoisted) so the test can drive them directly.

## Use case test pattern

```kotlin
class GetPhotosUseCaseTest {
    @Test
    fun returnsNotFoundWhenRepoEmpty() = runTest {
        val repo = FakeUserRepository()
        val useCase = GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler))
        val result = useCase()
        assertEquals(Err(PhotosError.NotFound), result)
    }
}
```

## Running on a device or emulator

Unit tests run on the host (`jvmTest`, `iosSimulatorArm64Test`); checking the app itself on Android
uses Google's **Android CLI** (`android`), which wraps the
emulator, install/launch and UI inspection:

```bash
android info                                   # SDK path + connected devices/emulators
android emulator list                          # AVDs
android emulator start <avd>                   # returns once booted
./gradlew :androidApp:assembleDebug
android run --apks androidApp/build/outputs/apk/debug/androidApp-debug.apk --device emulator-5554
android layout --device emulator-5554 --pretty # UI tree as JSON (text, bounds, center)
android screen capture --device emulator-5554 -o screen.png
adb -s emulator-5554 shell input tap <x> <y>   # interact via `center` coordinates from `layout`
android emulator stop <avd>
```

- **Emulator first for ad-hoc work.** Agents never install or launch on a **physical** device
  without the user's explicit OK — it's the user's phone. The exception is the `kmp-qa` agent (below),
  which may use a connected phone under strict rules. When more than one device is attached, always
  pass `--device <serial>` / `adb -s <serial>`.
- Worth a run after DI or navigation changes: launch, rotate (`adb shell settings put system
  user_rotation 1`), background + `adb shell am kill <appId>` + relaunch — that exercises Koin
  start-up, the Nav 3 back-stack save/restore (routes must be registered in `AppNavigation.kt`)
  and the feature's string resources being packaged.
- Install the CLI if `android` is missing: see `/kmp-forge-doctor`.

## Acceptance: scenarios → tagged tests → QA

With OpenSpec, a change's acceptance criteria are its spec **scenarios** (`#### Scenario: <name>` with WHEN / THEN). Each one gets a test that names it — a `// Scenario: <exact scenario name>` comment on the test (rule in `openspec/config.yaml`; the spec critic checks `tasks.md` plans it):

```kotlin
// Scenario: Picked theme survives a restart
@Test
fun pickedThemeIsRestored() = runTest {
    val repo = FakeSettingsRepository(stored = ThemeMode.DARK)
    val vm = SettingsViewModel(GetThemeUseCase(repo, TestDispatcherProvider(testScheduler)))
    vm.testWithInternalState(this, SettingsState.Initial) {
        containerHost.load()
        expectInternalState { copy(theme = ThemeMode.DARK) }
    }
}
```

The tag is how coverage is traced: the **`kmp-qa` agent** (QA engineer) maps every scenario of a change to its tagged test, flags missing or hollow ones, and — in device mode — runs each **user-visible** scenario as an Android CLI journey on a device (fresh app per journey, screenshots at every check, logcat for crashes, plus a rotation / process-death pass on changed screens), writing `build/qa/<change>/report.md`. It reports PASS / FAIL / ERROR, never edits code, and returns ERROR rather than PASS when it could not verify something.

Device choice: the one you name (serial or AVD), else a running emulator, else a connected **physical** device, else an AVD it boots. On a phone it touches only the app under test (installs the debug APK, clears only that app's data — and only once its debug build installed over it), never uninstalls a differently-signed copy such as your store install, skips a locked screen rather than unlocking it, and restores the rotation settings it changes.

- **Supervised:** after `/opsx:apply`, ask for the `kmp-qa` agent ("QA the `<change>` change", optionally naming the device).
- **Autonomous loop:** a third reviewer in the code gate — `qa: device | tests-only | off` (+ `qa-device: auto | <serial> | <AVD>`) in `openspec/AUTOLOOP.md`. Its blocking findings block the merge like any other.
- **Scope:** journeys run on Android; iOS / desktop / web behavior rests on the tagged tests. QA checks that the app *does* what the scenario says, not how it looks.

## What to test

- **Always**: every OpenSpec scenario — a test tagged `// Scenario: <name>` (see above).
- **Always**: every use case (happy path + each `DomainError` branch).
- **Always**: every ViewModel intent's state transitions.
- **Often**: data layer mappers (`Dto.toDomain()`) when transformation is non-trivial.
- **Sometimes**: reusable `:ui` Composables when they encode logic (sorting, filtering).
- **Skip in v1**: full screen integration tests (slow, brittle); screenshot tests (add per-project when needed).
