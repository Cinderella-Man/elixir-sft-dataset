Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file. This variation adds a **deterministic virtual-time scheduler**: the fake clock can register deferred callbacks that fire when virtual time is advanced past their due instant.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts an optional `:initial` datetime (defaults to `~U[2024-01-01 00:00:00Z]`) and an optional `:name` for registration.
- `Clock.Fake.now(server)` — returns the current virtual datetime.
- `Clock.Fake.advance(server, duration)` — moves virtual time forward. `duration` is a keyword list like `[seconds: 30]` or `[hours: 1, minutes: 30]` (supported units: `:second(s)`, `:minute(s)`, `:hour(s)`, `:day(s)`). Advancing must **fire every registered timer whose due instant is at or before the new virtual time**, executing their functions in chronological order (ties broken by registration order). It returns the list of fired timer refs, in fire order.
- `Clock.Fake.schedule(server, duration, fun)` — registers a 0-arity function `fun` to run when virtual time reaches `now + duration`. Returns a unique integer timer ref. Timers only ever fire during an `advance/2` call (never at scheduling time).
- `Clock.Fake.cancel(server, ref)` — cancels a still-pending timer. Returns `:ok` if it was pending, `:error` otherwise.
- `Clock.Fake.pending(server)` — returns the count of timers not yet fired or cancelled.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (`Clock.Real`) or a `Clock.Fake` PID/registered name and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument. This lets application code accept a `:clock` dependency-injection option and call `Clock.now(clock)` uniformly.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.