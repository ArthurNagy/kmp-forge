# Testing

## Layout

```
:domain/src/commonTest/         use case tests
:data/src/commonTest/           repository tests with FakeXxxDataSource
:data/src/jvmTest/              optional: MockK for third-party platform deps
:feature-*/src/commonTest/      ViewModel tests with ContainerHost.test()
:ui/src/commonTest/             optional: Composable behavior tests
```

## Frameworks

- **Assertions**: `kotlin.test` stdlib in `commonTest`. No Kotest unless a specific feature needs DSL/property tests.
- **MVI tests**: Orbit's `ContainerHost.test()` for happy-path state transitions.
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

`Result`/`Ok`/`Err` are [kotlin-result](https://github.com/michaelbull/kotlin-result) (`com.github.michaelbull.result.*`), not `kotlin.Result`. `UserError.NotFound` is a `sealed interface UserError : DomainError` case.

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
    fun `load sets photos on success`() = runTest {
        val repo = FakeUserRepository().apply { seed(samplePhoto) }
        val vm = GalleryViewModel(GetPhotosUseCase(repo, TestDispatcherProvider()))

        vm.test(this, GalleryState.Initial) {
            expectInitialState()
            containerHost.load()
            expectState { copy(loading = true) }
            expectState { copy(loading = false, photos = listOf(samplePhoto)) }
        }
    }

    @Test
    fun `load surfaces error on failure`() = runTest {
        val repo = FakeUserRepository().apply { nextError = DomainError.NetworkUnavailable }
        val vm = GalleryViewModel(GetPhotosUseCase(repo, TestDispatcherProvider()))

        vm.test(this, GalleryState.Initial) {
            containerHost.load()
            expectState { copy(loading = true) }
            expectState { copy(loading = false, error = DomainError.NetworkUnavailable) }
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

Every use case takes a `DispatcherProvider`. In tests, provide a `TestDispatcherProvider` backed by `StandardTestDispatcher`:

```kotlin
class TestDispatcherProvider(
    private val testDispatcher: TestDispatcher = StandardTestDispatcher(),
) : DispatcherProvider {
    override val main = testDispatcher
    override val io = testDispatcher
    override val default = testDispatcher
}
```

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
    fun `returns NotFound when repo empty`() = runTest {
        val repo = FakeUserRepository()
        val useCase = GetPhotosUseCase(repo, TestDispatcherProvider())
        val result = useCase()
        assertEquals(Err(PhotosError.NotFound), result)
    }
}
```

## What to test

- **Always**: every use case (happy path + each `DomainError` branch).
- **Always**: every ViewModel intent's state transitions.
- **Often**: data layer mappers (`Dto.toDomain()`) when transformation is non-trivial.
- **Sometimes**: reusable `:ui` Composables when they encode logic (sorting, filtering).
- **Skip in v1**: full screen integration tests (slow, brittle); screenshot tests (add per-project when needed).
