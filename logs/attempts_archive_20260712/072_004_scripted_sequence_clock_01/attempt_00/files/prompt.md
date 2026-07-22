Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation makes the fake clock **scripted**: instead of a single frozen value, it returns a predetermined sequence of timestamps, one per read, which is ideal for testing code that reads the clock several times.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts:
  - `:script` — a non-empty list of `DateTime`s to hand out, one per `now/1` call (defaults to `[~U[2024-01-01 00:00:00Z]]`).
  - `:on_exhaust` — the policy applied once the script is consumed. One of `:repeat_last` (default — keep returning the final value), `:cycle` (wrap around to the start), or `:raise` (raise a `RuntimeError`).
  - `:name` — an optional registration name.
  - Starting with an empty script, a non-`DateTime` element, or an unknown policy must fail to start.
- `Clock.Fake.now(server)` — returns the next scripted `DateTime`, advancing the internal cursor. Behaviour after the script is exhausted follows `:on_exhaust`.
- `Clock.Fake.remaining(server)` — returns how many scripted values have not yet been consumed.
- `Clock.Fake.reset(server)` — rewinds the cursor to the beginning of the script.
- `Clock.Fake.push(server, datetimes)` — appends more `DateTime`s to the end of the script.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.