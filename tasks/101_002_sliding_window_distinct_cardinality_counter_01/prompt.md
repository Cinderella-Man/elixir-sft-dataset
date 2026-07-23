**Ticket:** Implement `SlidingUniqueCounter`, an Elixir GenServer that tracks the number of **distinct members** seen for a key within a sliding time window using a sub-bucket strategy.

**Scope**
- Unlike a plain event counter, this counter answers "how many *unique* things did we see", not "how many events happened". Adding the same member many times inside the window still counts as one.
- Deliver the complete module in a single file.
- OTP standard library only; no external dependencies.

**Public API — `SlidingUniqueCounter.start_link(opts)`**
- Starts the process. Returns `{:ok, pid}` on success, like a standard GenServer start.
- Accepts `:clock` — a zero-arity function returning the current time in milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:bucket_ms` — the width of each internal sub-bucket in milliseconds. Defaults to `1_000` (1 second).
- Accepts `:name` — optional process registration name. When given, the whole API must be usable by passing that name in place of the pid.
- Accepts `:cleanup_interval_ms` — how often to run the periodic cleanup. Defaults to `60_000`. Pass `:infinity` to disable.
- Accepts `:max_window_ms` — the retention horizon used by cleanup: buckets whose start time is older than `now - max_window_ms` are removed. Defaults to `3_600_000` (1 hour).

**Public API — operations**
- `SlidingUniqueCounter.add(server, key, member)` — records that `member` was observed for the given `key` at the current clock time. Returns `:ok`.
- `SlidingUniqueCounter.distinct_count(server, key, window_ms)` — returns the number of **distinct** members observed for `key` that fall within the last `window_ms` milliseconds relative to the current clock time. Members observed only outside that window must not be counted. Returns `0` for a key that has never been added.
- `SlidingUniqueCounter.tracked_key_count(server)` — returns how many keys currently hold any tracked data at all (0 once cleanup has removed everything).

**Counting semantics**
- Adding the same member more than once (whether in the same instant or spread across time) counts that member exactly **once** within a window.
- A member observed in more than one in-window bucket is still counted once — the answer is the size of the union of all in-window buckets.
- A member counts if it was observed at least once inside the window, even if it was also observed outside the window.

**Internal design — bucketing**
- Divide time into fixed-width sub-buckets of `:bucket_ms` each. Every observation is placed into the bucket whose index is `div(timestamp, bucket_ms)`. Each bucket stores the **set** of distinct members observed inside it.
- When answering `distinct_count/3`, only include buckets whose start time is at or after `now - window_ms`. A bucket at index `b` starts at `b * bucket_ms`.
- Discard (do not count) any bucket whose start time falls before `now - window_ms`. Concretely, a member counts when the START of its bucket (`b * bucket_ms`) satisfies `b * bucket_ms >= now - window_ms` — bucket granularity, not per-observation timestamps, decides inclusion.
- Different keys must be tracked independently — adding to "page:home" must not affect "page:about".

**Internal design — cleanup / memory**
- Memory must not leak: run a periodic cleanup (via `Process.send_after`) that removes all buckets — and whole keys — that have fallen outside the `:max_window_ms` retention horizon.
- A bucket is kept only while its start time satisfies `b * bucket_ms >= now - max_window_ms`; older buckets are dropped, and a key with no remaining buckets is dropped entirely.
- Cleanup must keep the live buckets of a key even when it drops that key's expired ones.
- The periodic cleanup must re-schedule itself so data that expires later is still reclaimed — unless `:cleanup_interval_ms` is `:infinity`, in which case no periodic cleanup ever runs.
- Also handle a `:cleanup` message sent directly to the process so tests can trigger cleanup synchronously.
- After cleanup, `tracked_key_count/1` must report `0` when all data has expired.
