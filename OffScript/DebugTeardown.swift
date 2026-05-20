#if DEBUG
import Foundation
import SwiftData

/// One-stop singleton tear-down for the test suite.
///
/// **Why this exists.** `static let shared` instances are process-scoped;
/// SwiftData `ModelContainer`s are run-scoped. Any singleton that caches
/// an `@Model` reference (`Episode`, `Podcast`, …) — or a `ModelContext`,
/// or a `Combine` subscription on `@Model.publisher`, or an in-flight
/// `Task` / `URLSessionTask` whose completion touches a `@Model` ref —
/// will outlive the container that owns those refs. The next test sees
/// the singleton dereference into a torn-down container and crashes
/// somewhere innocent-looking (an `objectWillChange`, a Combine sink, a
/// delegate callback). See `docs/TEST_MATRIX.md` § "Lurking Crash Class".
///
/// **How to use.** Call `DebugTeardown.resetAllSingletons()` at the top
/// of every integration test that touches any singleton — or in the
/// test's `tearDown`. Cheap (a few dictionary clears + cancel calls),
/// idempotent, and works whether or not the singleton was actually
/// touched by the test.
///
/// **Adding a new singleton?** If your new `static let shared = Foo()`
/// holds a `ModelContext`, an `@Model`-typed property, a Combine
/// subscription on `@Model.publisher`, or a background `Task` that
/// touches `@Model` refs, wire it in here. Adding new singletons to
/// `resetAllSingletons()` is a forcing function — future test authors
/// don't have to remember each one. If your singleton is `@MainActor`
/// add a corresponding `@MainActor` call below; for non-isolated
/// singletons the call can sit outside the actor hop.
///
/// **Scoping.** `#if DEBUG` keeps the helper out of release builds. The
/// individual `debugResetForTesting()` methods on each singleton are
/// also `#if DEBUG`, so adding one here without the matching `#if DEBUG`
/// on the singleton would fail to compile in Release — that's the
/// intended contract.
@MainActor
enum DebugTeardown {
    static func resetAllSingletons() {
        // PlaybackController itself also resets NowPlayingPublisher
        // (its Combine subscriptions on `$currentEpisode` need to die
        // before currentEpisode goes nil, otherwise a sink could fire on
        // a stale @Model ref). We still call NowPlayingPublisher
        // explicitly below so this list is the canonical roster — a
        // future change to PlaybackController.debugResetForTesting()
        // that drops the publisher reset doesn't silently break test
        // isolation.
        PlaybackController.shared.debugResetForTesting()
        NowPlayingPublisher.shared.debugStopForTesting()
        DownloadService.shared.debugResetForTesting()
        BatchImportService.shared.debugResetForTesting()
        // Add other singletons here as they grow @Model refs.
    }
}
#endif
