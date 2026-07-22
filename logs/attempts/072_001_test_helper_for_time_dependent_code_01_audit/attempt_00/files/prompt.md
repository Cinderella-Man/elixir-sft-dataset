Write me an Elixir `Clock` behaviour and two implementations — one for production, one for testing — in a single file.

The behaviour should define one callback: `now/0`, returning the current time as a `DateTime`.

The production implementation `Clock.Real` should implement `now/0` by delegating to `DateTime.utc_now()`.

The test implementation `Clock.Fake` should be a `GenServer` with the following public API:
- `Clock.Fake.start_link(opts)` — starts the process. Accepts an optional `:initial` datetime (defaults to `~U[2024-01-01 00:00:00Z]`) and an optional `:name` for registration.
- `Clock.Fake.now(server)` — returns the currently frozen datetime.
- `Clock.Fake.freeze(server, datetime)` — sets the clock to a specific `DateTime`, replacing whatever time was there.
- `Clock.Fake.advance(server, duration)` — moves the clock forward. `duration` should be a keyword list like `[seconds: 30]` or `[hours: 1, minutes: 30]`, applied via `DateTime.add/4`.

Additionally, provide a top-level `Clock` module with a `now/1` function that accepts a module name (either `Clock.Real` or a `Clock.Fake` PID/registered name) and dispatches correctly — calling `Clock.Real.now()` or `Clock.Fake.now(server)` depending on the argument type. This lets application code accept a `:clock` dependency injection option and call `Clock.now(clock)` uniformly without caring which implementation is underneath.

Give me the complete implementation in a single file with no external dependencies, using only the Elixir standard library and OTP.