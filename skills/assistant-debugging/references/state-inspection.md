# Inspecting runtime state

Load for a specific runtime-state question in Python, Node or .NET that the
reproduction, traceback or logs cannot answer. Start from what the failure
already printed; inspect only for the value or state still unknown.

## Common rules

- **Non-interactive first.** Prefer output the runner already prints and
  scripted inspection. An interactive pause (a debugger prompt) under an
  output-capturing runner or in a non-TTY shell can hang the process, because
  nothing can answer the prompt.
- **Never block the shell on a paused process.** Start an inspector or a
  process that waits for a debugger in the background, with its output
  redirected to a file outside the repository; read the endpoint from that file
  and record the process ID so cleanup can terminate it. Bound every collection
  by a duration or an exit condition.
- **Loopback only.** Bind any inspection endpoint to loopback (`127.0.0.1`).
  Do not assume a default port; request an automatic port where the tool
  supports it and read the actual endpoint from the target process's output.
- **Helpers only when available.** Before using a helper (`debugpy`, a CDP
  client, `dotnet-dump`, `dotnet-trace`), check it is already installed. If it
  is missing, ask the user before installing it and wait for an explicit yes;
  otherwise use the built-in route or report the blocker. No helper becomes a
  dependency of the project.
- **No elevation.** Never elevate privileges or change a system ptrace
  setting. If an attach is refused, report the blocker.
- **Sensitive output.** Process dumps, traces and printed locals can hold
  secrets or private data. Capturing them keeps the authorisation rule for
  sensitive diagnostics in `SKILL.md`; quote only the values the question
  needs.
- **Clean up before handoff.** Resume or terminate every debugger session and
  paused process started for diagnosis. Remove temporary breakpoints,
  `breakpoint()`/`set_trace()` calls, `Debugger.Launch()`/`Debugger.Break()`
  calls and inspector flags added to source or configuration. Delete diagnostic
  output written outside the repository. Report anything that could not be
  cleaned up, for example "inspector target terminated; temporary
  `breakpoint()` removed from `cart.py` (git diff clean for that file)".
- **Repetition.** Repeated inspection attempts are governed only by the shared
  stagnation guard that `SKILL.md` loads; this reference adds no count.

## Python

1. Re-run only the failing test with full traceback and locals, for example
   `pytest path/to/test_file.py::test_name --showlocals --tb=long`.
2. If a value is still unknown, use scripted post-mortem inspection. For a
   failing test, call the failing code from a throwaway script outside the
   repository that catches the exception and prints the needed values from the
   traceback frames (`exc.__traceback__`, each frame's `f_locals`). For a plain
   script, run it under `python -m pdb -c continue <script>` and feed the
   commands on standard input, ending with `q`, so pdb prints the needed values
   at the failure and exits. A test runner catches the exception itself, so pdb
   run around the runner never reaches the failing frame.
3. Use `pdb` or `breakpoint()` only in an interactive terminal the user is
   driving, with output capture off (`-s`); never under a capturing or
   parallel runner in a non-interactive shell.
4. For a long-lived or remote process, use `debugpy` only after confirming it
   is installed. Start it on loopback with port 0, for example
   `debugpy.listen(("127.0.0.1", 0))`, and print the returned host and port,
   which is the actual endpoint. The user attaches their IDE to that endpoint
   unless a debug-adapter client is already available. Remove the call at
   cleanup.

## Node

1. Read the full stack trace first. For transpiled code, re-run with
   `--enable-source-maps` so frames point at the original source.
2. When a value at a specific point is still unknown, start the process with
   `node --inspect=127.0.0.1:0 <script>` (or `--inspect-brk=127.0.0.1:0` to
   stop before user code, only when a client or the user will attach). Run it
   in the background. Port 0 picks a free port; read the actual endpoint from
   the `Debugger listening on ws://…` line on standard error.
3. Set breakpoints through a CDP client only if one is already available.
   Otherwise give the user the `ws://` endpoint and the breakpoint location to
   attach from their own debugger, and wait for the observed value.
4. For child processes, pass the flag through
   `NODE_OPTIONS="--inspect=127.0.0.1:0"`; each Node child then prints its own
   endpoint.
5. A process that was started without an inspector is restarted with the flag;
   do not rely on a signal that opens a default port.

## .NET

1. **Exception and stack first.** Read the exception type, message, inner
   exceptions and stack trace the failing test or process already printed (the
   full `Exception.ToString()` chain). This often answers the question without
   another tool.
2. **Identify the test runner** before choosing flags. `dotnet test` uses
   Microsoft.Testing.Platform mode when `global.json` sets
   `"test": { "runner": "Microsoft.Testing.Platform" }` (.NET 10 SDK and later;
   from .NET 11 the `DOTNET_TEST_RUNNER` environment variable can override it).
   Otherwise it uses VSTest mode.
3. **Re-run only the failing test** at a verbosity that prints the full
   failure:
   - VSTest: `dotnet test --filter "FullyQualifiedName~Namespace.ClassName.TestName" --logger "console;verbosity=detailed"`.
   - Microsoft.Testing.Platform: filter options belong to the test framework,
     so list them with `dotnet test --help`. MSTest accepts
     `--filter "FullyQualifiedName~Namespace.ClassName.TestName"`; xUnit.net uses
     its own `--filter-*` options. Add `--output Detailed` for full failure
     output.
   - A VSTest-mode run of Microsoft.Testing.Platform test apps (the project
     sets `TestingPlatformDotnetTestSupport`) silently ignores `--logger`; pass
     test-app options after `--`, for example for MSTest
     `dotnet test -p:TestingPlatformShowTestsFailure=true -- --filter "FullyQualifiedName~Namespace.ClassName.TestName"`.
4. **Runner diagnostics only when the runner misbehaves.** Write them outside
   the repository: VSTest `--diag <absolute path outside the repository>/vstest.log`;
   Microsoft.Testing.Platform `--diagnostic --diagnostic-output-directory <absolute path outside the repository>`.
   Delete them at handoff or report them.
5. **Dumps and traces only when already installed** and the exception route
   cannot answer the question, for example a hang. Check with
   `dotnet tool list -g` or `command -v dotnet-dump`. If the tool is missing,
   ask the user before installing it; without a yes, report the blocker. With
   authorisation for a sensitive diagnostic:
   - find the process with `dotnet-dump ps`;
   - capture with `dotnet-dump collect -p <PID> -o <path outside the repository>`;
   - read the managed stacks of all threads without an interactive shell:
     `dotnet-dump analyze <dump> -c "clrstack -all" -c exit`;
   - for event traces, bound the collection:
     `dotnet-trace collect -p <PID> --duration 00:00:00:30 -o <path outside the repository>`
     (duration format `dd:hh:mm:ss`); without a duration it runs until stopped.
   Never commit or quote a dump or trace beyond the stacks, events or values
   needed, and delete it at handoff or report it.
6. **Local only.** These tools attach through the runtime's local diagnostics
   channel to a process the same user owns. Configure no TCP diagnostic port
   and no remote debugger; a remote target is a network diagnostic that needs
   authorisation.
7. **Interactive stepping belongs to the user.** When only stepping can answer
   the question, give exact IDE attach steps: which process (for a paused test
   host, `VSTEST_HOST_DEBUG=1` under VSTest or `--debug` under
   Microsoft.Testing.Platform, a run the user starts), the breakpoint location
   and the value to read, then wait for the reported value. Avoid inserting
   `Debugger.Launch()`/`Debugger.Break()` under a non-interactive runner.
8. Report an async-blocking cause, such as `.Result` waiting on a
   continuation, as evidence with its stack; the fix follows the normal repair
   route.
