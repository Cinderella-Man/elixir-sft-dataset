Write me an Elixir module called `Metrics` that collects application metrics using ETS tables for fast, concurrent-safe storage.

I need these functions in the public API:
- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, amount \\ 1)` to atomically increment a named counter by `amount`. Counters are monotonically increasing and should never decrease. Use `:ets.update_counter` for atomicity.
- `Metrics.gauge(name, value)` to set a named gauge to an exact value. Gauges can go up or down freely — each call overwrites the previous value.
- `Metrics.get(name)` to return the current value of a metric by name, or `nil` if it doesn't exist.
- `Metrics.all()` to return all metrics as a map of `%{name => value}`.
- `Metrics.reset(name)` to set a metric back to `0` regardless of whether it is a counter or gauge.
- `Metrics.snapshot()` to return a point-in-time map of all current metrics, identical in shape to `all/0` but semantically communicating immutability of the returned data.

Counters and gauges can coexist in the same table — there is no need to declare a metric's type upfront; `increment` creates or bumps a counter entry and `gauge` creates or overwrites a gauge entry. The ETS table should be public and named so that `increment` can bypass the GenServer process for maximum throughput (i.e., the hot path for incrementing must not serialize through a GenServer `call`). The GenServer is only needed for initialisation and owning the table.

Give me the complete implementation in a single file. Use only OTP/stdlib — no external dependencies.