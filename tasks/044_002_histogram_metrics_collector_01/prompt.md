Write me an Elixir module called `Metrics` that collects **latency/size distributions** using ETS for fast, concurrent-safe storage. This is a histogram collector (Prometheus-style), not a scalar counter/gauge collector.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration (defaulting to `__MODULE__`) and a `:buckets` option: a sorted ascending list of integer upper bounds. Default to `[10, 50, 100, 500, 1000]`.
- `Metrics.observe(name, value)` to record a single integer observation (e.g. a request latency in ms) for the histogram `name`, returning `:ok`. `value` must be a non-negative integer. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS using `:ets.update_counter`. Recording an observation atomically bumps the total count, the running sum, and the count for the matching bucket. A value `v` falls into the bucket of the smallest boundary `b` such that `v <= b`; a value larger than every boundary falls into the implicit `+Inf` bucket.
- `Metrics.get(name)` to return the current summary of the histogram as a map `%{count: c, sum: s, average: avg, buckets: %{...}}`, or `nil` if nothing has ever been observed for `name`. The `:buckets` map is **cumulative** ("less-than-or-equal"): each configured boundary maps to the number of observations `<= that boundary`, plus an `:infinity` key mapping to the total count. `:average` is `sum / count` as a float (the average of an empty histogram never arises because `get` returns `nil` when there are no observations).
- `Metrics.all()` to return a map of `%{name => total_count}` across every histogram.
- `Metrics.reset(name)` to erase all recorded data for `name` so that a subsequent `get(name)` returns `nil`.

The ETS table must be public and named so `observe` can bypass the owning process for maximum throughput. The GenServer exists only to own the table and to hold the bucket configuration. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.
