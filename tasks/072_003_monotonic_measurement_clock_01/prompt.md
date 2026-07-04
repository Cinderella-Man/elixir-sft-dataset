Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation is about **monotonic elapsed-time measurement** rather than wall-clock timestamps: the clock exposes a monotonically increasing integer counter (like `System.monotonic_time/1`) and a helper to measure how much time a function "takes".

The behaviour should define one callback: `monotonic/1`, which takes a time unit and returns the current monotonic time as an `integer` in that unit.

The production implementation `Clock.Real` should implement `monotonic/1` by delegating to `System.monotonic_time/1`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts an optional `:initial` integer offset **in milliseconds** (defaults to `0`) and an optional `:name` for registration.
- `Clock.Fake.monotonic(server, unit \\ :millisecond)` — returns the current monotonic value converted to `unit`. Support at least `:second`, `:millisecond`, `:microsecond`, and `:nanosecond`.
- `Clock.Fake.advance(server, duration)` — moves the counter forward. `duration` is a keyword list like `[milliseconds: 250]` or `[seconds: 2, milliseconds: 500]` (supported units: `:microsecond(s)`, `:millisecond(s)`, `:second(s)`, `:minute(s)`, `:hour(s)`).

Additionally, provide a top-level `Clock` module with:
- `Clock.monotonic(clock, unit \\ :millisecond)` — dispatches to `Clock.Real.monotonic(unit)` when given the `Clock.Real` module atom, or to `Clock.Fake.monotonic(server, unit)` when given a `Clock.Fake` PID/registered name.
- `Clock.measure(clock, fun)` — reads the monotonic clock (in microseconds) before and after invoking the 0-arity `fun`, and returns `{result, elapsed_milliseconds}` where `result` is `fun`'s return value and `elapsed_milliseconds` is the integer millisecond delta. With `Clock.Fake`, `fun` advancing the clock makes elapsed time fully deterministic.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.