---
name: presentation-layer
description: Write or change UI code in a kmp-forge project — :feature-* screens, Orbit ViewModels with state-only events (consumable state slots, never postSideEffect), State without defaults plus Initial, the Screen/Content split, Nav 3 routes and entry contributions with outgoing navigation as callbacks, Koin viewModelOf, feature string resources and DomainError-to-text mapping, accessibility and RTL, :ui tokens and shared composables, and ViewModel tests with Orbit's harness. Use when building or changing a screen, ViewModel or UI state, navigation between screens or features, a shared composable or design token, or when an OpenSpec task touches :feature-* or :ui.
---

# Presentation (`:feature-*` and `:ui`) — kmp-forge style

A feature module is presentation only: screens, their ViewModels and state, its navigation entries and strings. Business logic comes from `:domain` use cases (see the `domain-layer` skill), and the app composes features in `:shared`. Canonical rules: the plugin's [architecture.md](../../docs/architecture.md) (§ `:feature-<name>`, § ViewModel + Orbit pattern, § Navigation wiring, § Visibility), [stack.md](../../docs/stack.md) (Orbit, Koin, Nav 3), [i18n-a11y.md](../../docs/i18n-a11y.md) and [testing.md](../../docs/testing.md).

## Start from the generators

- New feature: `/kmp-forge-add-feature <name>`. New screen in an existing feature: `/kmp-forge-add-screen <feature> <screen>`. They render the template **and** wire `:shared` (Koin module list, route registration, `entryProvider`). Don't hand-roll a feature module; this skill is about filling one in.
- `:feature-*` depends on `:domain` and `:ui` only: never `:data`, never another feature.

| Lives in | What |
|---|---|
| `:feature-<name>` | **public:** `XRoute`, the Koin module, `addXEntries(...)`. **internal:** `XScreen`, `XViewModel`, `XState`. **private:** `XContent`. Strings in its own `composeResources/values/strings.xml`. |
| `:ui` | `AppTheme`, tokens (`AppSpacing`, `AppDimens`, `AppColors`, `AppType`), stateless composables used by two or more features |
| `:shared` | the back stack, route registration, and the callbacks that connect features, at its `// kmp-forge:` markers |

## State

```kotlin
internal data class PhotosState(
    val loading: Boolean,
    val photos: List<Photo>,
    val error: PhotoError?,
    // Consumable slots: set by an intent, cleared by the paired onXConsumed() after the UI acts on them.
    val pendingOpenPhoto: PhotoId?,
    val pendingMessage: StringResource?,
) {
    companion object {
        val Initial = PhotosState(
            loading = false,
            photos = emptyList(),
            error = null,
            pendingOpenPhoto = null,
            pendingMessage = null,
        )
    }
}
```

- **No constructor defaults.** `Initial` is the single starting value, used by `orbitContainer(...)` and every test.
- Type `error` with the area's sealed error (`PhotoError?`), so the UI can map it exhaustively. The template's `DomainError?` is only the generic starting point.
- A message slot carries *which* message, not its text: a `StringResource` (`org.jetbrains.compose.resources`) that the Screen resolves. The template declares `pendingMessage: String?`; give it the resource type when the screen first shows a message, so no literal text sits in the ViewModel.
- Mutually exclusive page states (`Loading | Loaded | Error`) that turn into boolean tangles: use a `sealed interface XState` whose starting state is an explicit object. Default to the flat data class.
- Everything that must survive rotation or process death, or that an intent needs, goes in `State`. Only UI-local details (scroll position, an open dropdown) may live in `remember`.

## ViewModel

```kotlin
internal class PhotosViewModel(
    private val getPhotos: GetPhotosUseCase,
    private val toggleFavorite: ToggleFavoriteUseCase,
) : ViewModel(), OrbitContainerHost<PhotosState, PhotosState, Nothing> {

    override val container = orbitContainer<PhotosState, Nothing>(PhotosState.Initial)

    fun load() = intent {
        reduce { state.copy(loading = true, error = null) }
        getPhotos()
            .onOk { photos -> reduce { state.copy(loading = false, photos = photos) } }
            .onErr { error -> reduce { state.copy(loading = false, error = error) } }
    }

    fun onFavoriteClicked(id: PhotoId) = intent {
        toggleFavorite(id)
            .onOk { updated -> reduce { state.copy(photos = state.photos.map { if (it.id == id) updated else it }) } }
            .onErr { reduce { state.copy(pendingMessage = Res.string.favorite_failed) } }
    }

    fun onPendingMessageConsumed() = intent { reduce { state.copy(pendingMessage = null) } }
}
```

- `androidx.lifecycle.ViewModel` + `OrbitContainerHost<S, S, Nothing>` + `orbitContainer<S, Nothing>(S.Initial)` (Orbit 12). No custom base class, no deprecated `ContainerHost` / `container(...)`.
- **State-only events.** The side-effect type is always `Nothing`: no `postSideEffect`, no `XEffect` type. A one-shot event (navigate, show a snackbar) is a `pendingX` slot plus a `fun onXConsumed()` intent that clears it.
- Every state change happens inside `intent { reduce { … } }`.
- The constructor takes **use cases only**: never a repository, never `DispatcherProvider`. Orbit runs intents off the main thread, and use cases switch dispatchers themselves.
- Consume `Result` with `onOk` / `onErr` (explicit imports from `com.github.michaelbull.result`). No `try/catch` in an intent: use cases don't throw.
- Observe a stream only while the screen is visible: `fun observe() = intent { repeatOnSubscription { favorites().collect { reduce { state.copy(favorites = it) } } } }`.

## Screen and Content

```kotlin
@Composable
internal fun PhotosScreen(
    onOpenPhoto: (PhotoId) -> Unit,
    onNavigateBack: (() -> Unit)?,
) {
    val viewModel = koinViewModel<PhotosViewModel>()
    val state by viewModel.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) { viewModel.load() }
    LaunchedEffect(state.pendingMessage) {
        val message = state.pendingMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(getString(message))
        viewModel.onPendingMessageConsumed()
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

- `XScreen` (internal) resolves the ViewModel with `koinViewModel<XViewModel>()` **in its body**. A `viewModel = …` default parameter would leak the internal type. The Screen collects state, runs one `LaunchedEffect` per consumable slot (act, then call `onXConsumed()`), and passes lambdas down.
- `XContent` (private) is stateless: state plus lambdas, no ViewModel, no Koin. Host the `SnackbarHost` in its `Scaffold`, or `showSnackbar` never returns.
- **Navigation.** A tap that only navigates calls the callback directly (`onPhotoClick = onOpenPhoto`). Navigation that depends on an outcome ("after the save succeeds") goes through a slot: the intent sets `pendingOpenPhoto`, and the Screen's `LaunchedEffect` calls `onOpenPhoto(it)` and then `onOpenPhotoConsumed()`. A slot holds the navigation argument (or this feature's own route), never another feature's route.

## Navigation 3

- A route is public and `@Serializable`: `data object PhotosRoute : NavKey`, or `data class PhotoDetailRoute(val id: String) : NavKey`. Arguments are small (an ID, not an object), because the back stack is saved and restored.
- **Route arguments reach the screen through the entry:** `entry<PhotoDetailRoute> { route -> PhotoDetailScreen(id = PhotoId(route.id), onNavigateBack = onNavigateBack) }`. The screen hands them to an intent (`LaunchedEffect(id) { viewModel.load(id) }`). Each back-stack entry gets its own ViewModel (`rememberViewModelStoreNavEntryDecorator`), so the constructor stays injection-only.
- **Outgoing navigation is a callback parameter** on `addXEntries(...)`. The app supplies it in `AppNavigation.kt` (`onOpenPhoto = { backStack.add(PhotoDetailRoute(it.value)) }`). A feature never imports another feature's route.
- A new route must be registered in `AppNavigation.kt`'s `SerializersModule` (the `// kmp-forge:nav-routes` marker). Otherwise saving the back stack throws on iOS, desktop and web. `/kmp-forge-add-screen` does it.
- The start destination is wired with `onNavigateBack = null`, and its screen shows no Back control.

## Koin

One module per feature, `val photosModule = module { viewModelOf(::PhotosViewModel) }`, listed in `:shared`'s `AppModules.kt` (`/kmp-forge-add-feature` adds it). Never construct a ViewModel by hand, never `KoinComponent` / `GlobalContext.get()`.

## Strings and errors

- Every user-facing string, `contentDescription` included, comes from the feature's own `src/commonMain/composeResources/values/strings.xml`. The **unqualified `values/` table must define every key**: Compose falls back only to it, and a key that exists only in `values-en/` crashes every other locale. Translations (`values-fr/`) may omit keys. `Res` is generated `internal` into `<base>.feature.<pkg>.resources`.
- Errors become text in the UI, exhaustively, with one resource per case:

  ```kotlin
  @Composable
  private fun PhotoError.message(): String = stringResource(
      when (this) {
          PhotoError.NotFound -> Res.string.error_not_found
          PhotoError.Offline -> Res.string.error_offline
          PhotoError.Unavailable -> Res.string.error_unavailable
          PhotoError.TitleBlank -> Res.string.error_title_blank
      },
  )
  ```
  Never render a `DomainError` directly.
- Counts use `pluralStringResource(Res.plurals.photo_count, count, count)`.
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

`feature-<name>/src/commonTest/`: test **every intent's state transitions**, including the error branch and the clearing of each consumable slot. Build **real use cases over fakes** from `:testing` (use cases are final classes; there are no fake use cases).

```kotlin
class PhotosViewModelTest {
    @Test
    fun loadShowsPhotos() = runTest {
        val photo = photo(id = "1", title = "a")
        val repo = FakePhotoRepository().apply { seed(photo) }
        val vm = PhotosViewModel(
            GetPhotosUseCase(repo, TestDispatcherProvider(testScheduler)),
            ToggleFavoriteUseCase(repo),
        )

        vm.testWithInternalState(this, PhotosState.Initial) {       // Orbit 12: initial state asserted automatically
            containerHost.load()
            expectInternalState { copy(loading = true) }
            expectInternalState { copy(loading = false, photos = listOf(photo)) }
        }
    }
}
```

- Seed a starting state with `PhotosState.Initial.copy(pendingMessage = …)`, never a no-arg constructor.
- The generated `XViewModelTest` targets the template: a ViewModel with no constructor arguments and `pendingMessage = "Hi"`. Rewrite it as soon as the ViewModel takes use cases or a slot changes type. It stops compiling, which is the cue.
- Tag tests that cover an OpenSpec scenario with `// Scenario: <exact name>`. The `kmp-qa` agent traces coverage through the tag, then runs the user-visible scenarios on a device.
- Compose UI behavior (`runComposeUiTest`) drives the stateless Content through its `testTag`s. When a test needs `XContent`, widen it from `private` to `internal`, which is the visibility rule's own reason to widen.
- MockK never appears in `commonTest`. Turbine on `container.stateFlow` is for timing-sensitive cases (debounce).

## Before you hand it on

- The feature's public surface is exactly its route, module and `addXEntries`. No `:data` import, no other feature's route.
- No `postSideEffect`, no Effect type, no `try/catch` in an intent, no `Dispatchers.*`, no repository in a ViewModel.
- `State` has no defaults, `Initial` sets every field, and every `pendingX` slot has its `LaunchedEffect` and `onXConsumed()`.
- Every new route is registered in `AppNavigation.kt`. The start destination has `onNavigateBack = null`.
- Every string is in `values/strings.xml`, the template placeholder is gone, and the accessibility checklist above holds.
- `./gradlew :feature-<name>:jvmTest` while iterating. Before pushing, run `./gradlew spotlessApply` (the samples here are compact, and ktlint_official reflows signatures and comments), then the CI gate: `./gradlew spotlessCheck detekt build koverVerify`. When the change is user-visible, ask for the `kmp-qa` agent to run its scenarios on a device.
