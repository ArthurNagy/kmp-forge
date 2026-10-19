---
name: presentation-layer
description: Write or change UI code in a kmp-forge project — :feature-* screens, Orbit ViewModels with state-only events (consumable state slots, never postSideEffect) that start their work in the container's on-create block, State without defaults plus Initial, the entry/Screen/Content split, route arguments passed to the ViewModel through Koin parameters, Nav 3 entry contributions with outgoing navigation as callbacks, errors rendered through :ui's DomainError.toMessage() with the screen wording its area's typed errors, feature string resources, accessibility and RTL, :ui tokens and shared composables, and ViewModel tests with Orbit's harness. Use in a kmp-forge project (its CLAUDE.md links kmp-forge's docs as its rules) when building or changing a screen, ViewModel or UI state, navigation between screens or features, a shared composable or design token, or when an OpenSpec task touches :feature-* or :ui.
---

# Presentation (`:feature-*` and `:ui`) — kmp-forge style

A feature module is presentation only: screens, their ViewModels and state, its navigation entries and strings. Business logic comes from `:domain` use cases (see the `domain-layer` skill), and the app composes features in `:shared`. Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ `:feature-<name>`, § ViewModel + Orbit pattern, § Navigation wiring, § Visibility), [stack.md](../../docs/stack.md) (Orbit, Koin, Nav 3), [i18n-a11y.md](../../docs/i18n-a11y.md) and [testing.md](../../docs/testing.md).

## Start from the generators

- New feature: `/kmp-forge-add-feature <name>`. New screen in an existing feature: `/kmp-forge-add-screen <feature> <screen>`. They render the template **and** wire `:shared` (Koin module list, route registration, `entryProvider`). Don't hand-roll a feature module; this skill is about filling one in.
- `:feature-*` depends on `:domain` and `:ui` only: never `:data`, never another feature.

| Lives in | What |
|---|---|
| `:feature-<name>` | **public:** `XRoute`, the Koin module, `addXEntries(...)`. **internal:** `XScreen`, `XViewModel`, `XState`. **private:** `XContent`. Strings in its own `composeResources/values/strings.xml`. |
| `:ui` | `AppTheme`, tokens (`AppSpacing`, `AppDimens`, `AppColors`, `AppType`), `DomainError.toMessage()`, stateless composables used by two or more features |
| `:shared` | the Koin start (`startAppKoin()`), the back stack, route registration, and the callbacks that connect features, at its `// kmp-forge:` markers |

## State

```kotlin
internal data class PhotosState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: DomainError?,
    // Consumable slots: set by an intent, cleared by the paired onXConsumed() after the UI acts on them.
    val pendingFavoriteFailure: Boolean,
    val pendingLeave: Boolean,
) {
    companion object {
        val Initial = PhotosState(
            loading = false,
            photos = emptyList(),
            error = null,
            pendingFavoriteFailure = false,
            pendingLeave = false,
        )
    }
}
```

- **No constructor defaults.** `Initial` is the single starting value, used by `orbitContainer(...)` and every test.
- `error: DomainError?` carries the error as-is: a built-in case, or the area's typed error (`PhotoError.AlbumFull(limit)`). The screen turns it into words (see *Strings and errors*).
- **A slot holds what happened, never resolved text:** a flag, a domain value (`downloadResult: TransferResult?`) or a `StringResource`. The screen turns it into words (`getString(…)` inside its `LaunchedEffect`), so no literal text sits in a ViewModel. The template's `pendingMessage: StringResource?` is the message slot; the screen resolves it with `getString(…)`.
- Mutually exclusive page states (`Loading | Loaded | Error`) that turn into boolean tangles: use a `sealed interface XState` whose starting state is an explicit object. Default to the flat data class.
- Everything that must survive rotation or process death, or that an intent needs, goes in `State`. Only UI-local details (scroll position, an open dropdown) may live in `remember`. Derived facts can be getters on the state (`val isSelectionMode get() = selectedIds.isNotEmpty()`).

## ViewModel

```kotlin
internal class PhotosViewModel(
    private val getPhotos: GetPhotosUseCase,
    private val toggleFavorite: ToggleFavoriteUseCase,
) : ViewModel(), OrbitContainerHost<PhotosState, PhotosState, Nothing> {

    override val container = orbitContainer<PhotosState, Nothing>(PhotosState.Initial) {
        load()                                        // once per ViewModel = once per back-stack entry
    }

    fun load() = intent {
        reduce { state.copy(loading = true, error = null) }
        getPhotos()
            .onOk { photos -> reduce { state.copy(loading = false, photos = photos) } }
            .onErr { error -> reduce { state.copy(loading = false, error = error) } }
    }

    fun onFavoriteClicked(id: PhotoId) = intent {
        toggleFavorite(id)
            .onOk { updated -> reduce { state.copy(photos = state.photos.map { if (it.id == id) updated else it }) } }
            .onErr { reduce { state.copy(pendingFavoriteFailure = true) } }
    }

    fun onFavoriteFailureConsumed() = intent { reduce { state.copy(pendingFavoriteFailure = false) } }

    // pendingLeave is set by whatever ends the screen's purpose (a session that ended, a finished flow).
    fun onLeaveConsumed() = intent { reduce { state.copy(pendingLeave = false) } }
}
```

- `androidx.lifecycle.ViewModel` + `OrbitContainerHost<S, S, Nothing>` + `orbitContainer<S, Nothing>(S.Initial)` (Orbit 12). No custom base class, no deprecated `ContainerHost` / `container(...)`.
- **Start work in the on-create block**: loads, and long-lived observations (`fun observeRoll() = intent { observeCameraRoll().collect { reduce { … } } }`). It runs once per ViewModel, which means once per back-stack entry. A `LaunchedEffect(Unit) { viewModel.load() }` in the screen would reload every time the user comes back.
- **State-only events.** The side-effect type is always `Nothing`: no `postSideEffect`, no `XEffect` type. A one-shot event (leave the screen, show a snackbar) is a `pendingX` slot plus a `fun onXConsumed()` intent that clears it.
- Every state change happens inside `intent { reduce { … } }`.
- The constructor takes **use cases**, plus any route argument first. Never a repository, never `DispatcherProvider`: Orbit runs intents off the main thread, and use cases switch dispatchers themselves. A long list of use cases is fine (`@Suppress("LongParameterList")` with a comment such as `// one use case per action`).
- Consume `Result` with `onOk` / `onErr` (explicit imports from `com.github.michaelbull.result`). No `try/catch` in an intent: use cases don't throw.

## Entry, Screen and Content

```kotlin
@Composable
internal fun PhotosScreen(
    onOpenPhoto: (PhotoId) -> Unit,
    onLeave: () -> Unit,
    onNavigateBack: (() -> Unit)?,
) {
    val viewModel = koinViewModel<PhotosViewModel>()
    val state by viewModel.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.pendingFavoriteFailure) {
        if (!state.pendingFavoriteFailure) return@LaunchedEffect
        snackbarHostState.showSnackbar(getString(Res.string.favorite_failed))
        viewModel.onFavoriteFailureConsumed()
    }
    LaunchedEffect(state.pendingLeave) {
        if (!state.pendingLeave) return@LaunchedEffect
        onLeave()
        viewModel.onLeaveConsumed()
    }

    PhotosContent(
        state = state,
        snackbarHostState = snackbarHostState,
        onPhotoClick = onOpenPhoto,                         // plain navigation: straight to the app's callback
        onFavoriteClick = viewModel::onFavoriteClicked,
        onRetry = viewModel::load,
        onNavigateBack = onNavigateBack,
    )
}
```

- `XScreen` (internal) resolves the ViewModel with `koinViewModel<XViewModel>()` **in its body**. A `viewModel = …` default parameter would leak the internal type. The screen collects state, runs one `LaunchedEffect` per consumable slot (act, then call `onXConsumed()`), and passes lambdas down. With many callbacks, group them in a remembered holder: `val actions = remember(viewModel) { PhotosActions(onFavoriteClick = viewModel::onFavoriteClicked, …) }`.
- `XContent` (private) is stateless: state plus lambdas, no ViewModel, no Koin. Host the `SnackbarHost` in its `Scaffold`, or `showSnackbar` never returns. Errors: `state.error?.let { Text(it.message()) }`, using the screen's own mapping (see *Strings and errors*).
- **Navigation.** A tap that only navigates calls the callback directly (`onPhotoClick = onOpenPhoto`). Navigation that depends on an outcome ("the session ended", "the save succeeded") goes through a slot that the screen's `LaunchedEffect` turns into the callback. A slot holds the navigation argument (or this feature's own route), never another feature's route.

## Navigation 3

- A route is public and `@Serializable`: `data object PhotosRoute : NavKey`, or `data class PhotoDetailRoute(val id: String) : NavKey`. Arguments are small (an ID, not an object), because the back stack is saved and restored.
- **Route arguments go into the ViewModel's constructor** through Koin parameters. The entry reads the route, and the screen asks Koin for a ViewModel keyed by the argument:
  ```kotlin
  // XModule.kt
  val photoDetailModule = module {
      viewModel { (id: String) -> PhotoDetailViewModel(id, get()) }   // org.koin.core.module.dsl.viewModel
  }
  // XNavEntry.kt
  entry<PhotoDetailRoute> { route -> PhotoDetailScreen(id = route.id, onNavigateBack = onPhotoDetailBack) }
  // PhotoDetailScreen.kt
  val viewModel = koinViewModel<PhotoDetailViewModel>(key = id, parameters = { parametersOf(id) })
  ```
  The on-create block then loads by `id`. A ViewModel without arguments stays `viewModelOf(::XViewModel)`. A pushed screen always gets a working Back: give it its own non-null callback (`onPhotoDetailBack: () -> Unit` on `addPhotosEntries`), because the feature's `onNavigateBack` is `null` when the feature's first screen is the start destination.
- **Outgoing navigation is a callback parameter** on `addXEntries(...)`. The app supplies it in `AppNavigation.kt` (`onOpenPhoto = { backStack.add(PhotoDetailRoute(it.value)) }`). A feature never imports another feature's route.
- A new route must be registered in `AppNavigation.kt`'s `SerializersModule` (the `// kmp-forge:nav-routes` marker). Otherwise saving the back stack throws on iOS, desktop and web. `/kmp-forge-add-screen` does it.
- The start destination is wired with `onNavigateBack = null`, and its screen shows no Back control.

## Koin

One module per feature, listed in `:shared`'s `AppModules.kt` (`/kmp-forge-add-feature` adds it). Koin starts once per process, at app launch, through `:shared`'s `startAppKoin()` (Android's `MainApplication`, iOS's `MainViewController()`, desktop/web `main()`), so services and background work share the screens' graph. Never start Koin inside composition, never construct a ViewModel by hand, never `KoinComponent` / `GlobalContext.get()`.

## Strings and errors

- Every user-facing string, `contentDescription` included, comes from the feature's own `src/commonMain/composeResources/values/strings.xml`. The **unqualified `values/` table must define every key**: Compose falls back only to it, and a key that exists only in `values-en/` crashes every other locale. Translations (`values-fr/`) may omit keys. `Res` is generated `internal` into `<base>.feature.<pkg>.resources`.
- **Errors.** `:ui`'s `DomainError.toMessage()` words the built-in cases (`Network.Connectivity`, `Network.Http`, `NotFound`, `Unknown`) once for the whole app; never re-word them in a feature. The screen words the area's **typed** errors it can react to, from its own string table, and falls back to `toMessage()` for everything else:

  ```kotlin
  @Composable
  private fun DomainError.message(): String = when (this) {
      PhotoError.TitleBlank -> stringResource(Res.string.photo_title_blank)
      is PhotoError.AlbumFull -> stringResource(Res.string.photo_album_full, limit)
      else -> toMessage()            // built-in cases, and typed errors this screen doesn't handle
  }
  ```
  A typed error can also drive more than text, such as a dialog or a different action (`if (state.error is PhotoError.AlbumFull) …`). Never show a `cause`.
- Counts use `pluralStringResource(Res.plurals.photo_count, count, count)`. Inside a `LaunchedEffect`, resolve with the suspending `getString(…)`.
- Remove the template's `placeholder_content` string and its `// TODO(kmp-forge):` line once the real content exists (`kmp-reviewer` flags a feature that still renders it).

## Composables, accessibility, RTL

- Sizes and gaps from `AppSpacing` / `AppDimens`, colors from `MaterialTheme.colorScheme`, text styles from `MaterialTheme.typography`. No `.sp` literals, and no color literals outside `:ui`.
- `Icon` / `Image` / `AsyncImage` (Coil) always pass `contentDescription`: a `stringResource`, or an explicit `null` when decorative.
- Touch targets are at least 48dp. Material components already are; a custom clickable gets `Modifier.minimumInteractiveComponentSize()`.
- RTL: `padding(start = …, end = …)`, `Alignment.Start` / `End`. Never `left` / `right` or `absoluteOffset`.
- `Modifier.testTag("<screen>:<element>")` (e.g. `photos:photo:${id}`) on every element a test or a QA journey must find.
- Rows that should announce as one item: `Modifier.semantics(mergeDescendants = true) {}`.

## `:ui`

A composable moves to `:ui` once a second feature needs it. It stays stateless (takes values and lambdas, plus `modifier: Modifier = Modifier`; the no-defaults rule covers entities and `State`, not Compose parameters). New tokens go into the token objects, and new colors into **both** light and dark schemes. Feature-specific composables stay `private` in their feature.

## Tests

`feature-<name>/src/commonTest/`: test **every intent's state transitions**, the on-create work, the error branch and the clearing of each consumable slot. Build **real use cases over fakes** from `:testing` (use cases are final classes; there are no fake use cases).

```kotlin
class PhotosViewModelTest {
    @Test
    fun creatingTheViewModelShowsThePhotos() = runTest {
        val photo = photo(id = "1", title = "a")
        val repo = FakePhotoRepository().apply { seed(photo) }
        val vm = PhotosViewModel(
            GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler)),
            ToggleFavoriteUseCase(repo),
        )

        vm.testWithInternalState(this, PhotosState.Initial) {       // Orbit 12: initial state asserted automatically
            runOnCreate()                                           // the on-create block runs only when asked
            expectInternalState { copy(loading = true) }
            expectInternalState { copy(loading = false, photos = listOf(photo)) }
        }
    }
}
```

- An on-create block that collects an endless flow never finishes. End such a test with `cancelAndIgnoreRemainingItems()`.
- Seed a starting state with `PhotosState.Initial.copy(pendingFavoriteFailure = true)`, never a no-arg constructor.
- Tag tests that cover an OpenSpec scenario with `// Scenario: <exact name>`. The `kmp-qa` agent traces coverage through the tag, then runs the user-visible scenarios on a device.
- Compose UI behavior (`runComposeUiTest`) drives the stateless Content through its `testTag`s. When a test needs `XContent`, widen it from `private` to `internal`, which is the visibility rule's own reason to widen.
- MockK never appears in `commonTest`. Turbine on `container.stateFlow` is for timing-sensitive cases (debounce).
- The generated `XViewModelTest` targets the template's ViewModel, which has no constructor arguments. Rewrite it as soon as the ViewModel takes use cases. It stops compiling, which is the cue.

## Before you hand it on

- The feature's public surface is exactly its route, module and `addXEntries`. No `:data` import, no other feature's route.
- No `postSideEffect`, no Effect type, no `try/catch` in an intent, no `Dispatchers.*`, no repository in a ViewModel. Work starts in the on-create block, not in a `LaunchedEffect(Unit)`.
- `State` has no defaults, `Initial` sets every field, and every `pendingX` slot has its `LaunchedEffect` and `onXConsumed()`.
- Errors are worded by the screen's typed-error mapping, falling back to `toMessage()`. Every new route is registered in `AppNavigation.kt`. The start destination has `onNavigateBack = null`.
- Every string is in `values/strings.xml`, the template placeholder is gone, and the accessibility checklist above holds.
- `./gradlew :feature-<name>:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify`. When the change is user-visible, ask for the `kmp-qa` agent to run its scenarios on a device.
