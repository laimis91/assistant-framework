# C# Review

Use with the triggered code sections when the material is C#. Sources:
[dispose](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/implementing-dispose),
[async](https://learn.microsoft.com/en-us/archive/msdn-magazine/2013/march/async-await-best-practices-in-asynchronous-programming),
[nullable](https://learn.microsoft.com/en-us/dotnet/csharp/nullable-references).

1. **Disposal**: the owner of an `IDisposable` disposes it; `Dispose` is idempotent; a non-sealed class uses `Dispose(bool)`; prefer `SafeHandle` over a finalizer; derived classes call `base.Dispose(disposing)`.
2. **Async**: no `async void` outside event handlers; no `.Result`/`.Wait()` (deadlock, `AggregateException`); no blocking inside `async` methods; async lambdas never become `Action`; `ConfigureAwait(false)` in library code; accept and pass `CancellationToken`; guard shared state across `await` (`SemaphoreSlim`, not `lock`).
3. **Nullability**: `<Nullable>` enabled; each `!` justified; required values non-nullable; no `default` structs or `new T[n]` leaving reference fields null; API contracts use nullable attributes.
4. **Exceptions**: catch the narrowest type; never swallow; rethrow with `throw;`; validate arguments at the boundary.
5. **Fit**: matches sibling code in naming, layering and test style.
