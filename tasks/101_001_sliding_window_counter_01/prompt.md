**Summary:** Implement `SlidingCounter`, an Elixir GenServer that counts events in a sliding time window via fixed-width sub-buckets. Single file, OTP standard library only, no external dependencies.

**Public API — `SlidingCounter.start_link(opts)`**
- Starts the process. `opts` is a keyword list and must be optional (default `[]`).
- Returns whatever `GenServer.on_start()` normally returns (`{:ok, pid}`, `{:error, {:already_started, pid}}`, …).
- `:clock` — zero-arity function returning current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`.
- `:clock` — every timestamp the server uses (increments, counts, cleanup) must come from calling this function at the moment it is needed, never from a cached value.
- `:clock` — may return negative integers (a monotonic clock legitimately can); every rule below must still hold for negative times.
- `:bucket_ms` — width of each internal sub-bucket in milliseconds. Default `1_000` (1 second).
- `:max_window_ms` — retention horizon used by cleanup: the oldest data the process promises to keep. Default `bucket_ms * 60` (one minute at the default bucket width; scales down automatically when a caller configures small buckets).
- `:cleanup_interval_ms` — how often the periodic cleanup runs. Default `60_000`. Pass `:infinity` to disable the periodic timer entirely.
- `:name` — optional process registration name. Must be forwarded to `GenServer.start_link/3` as a start option, not treated as counter config.

**Public API — `SlidingCounter.increment(server, key)`**
- Records one event for `key` at the current clock time. Returns `:ok`.
- `key` may be any term (binary, atom, tuple, …); keys are compared by value.
- Must be a **synchronous** call: when it returns, the event is already recorded and stamped, so a caller may advance its test clock or call `count/3` on the very next line and see the event.

**Public API — `SlidingCounter.count(server, key, window_ms)`**
- Returns a plain non-negative integer, not an `{:ok, _}` tuple: the total number of events recorded for `key` falling within the last `window_ms` milliseconds relative to the current clock time.
- Events outside that window must not be counted.
- Also a synchronous call.

**Bucketing**
- Divide time into fixed-width sub-buckets of `:bucket_ms` each.
- Each event goes into the bucket whose index is the *floor* division of its timestamp by `bucket_ms` — floor, not truncation; this is what keeps negative clock values sane.
- Bucket `b` covers the half-open interval `[b * bucket_ms, (b + 1) * bucket_ms)`.
- A bucket stores only an integer count, not individual timestamps; repeated increments landing in the same bucket simply add to that bucket's counter.

**Counting rule (exact, at the boundary)**
- For `count(server, key, window_ms)`: let `now` be the current clock reading and `window_start = now - window_ms`.
- A bucket is included **iff its start time is at or after `window_start`** — i.e. `b * bucket_ms >= now - window_ms`, equivalently `b >= ceil((now - window_ms) / bucket_ms)`.
- Included buckets contribute their count *in full*.
- Buckets that start before `window_start` contribute nothing at all, even if their range overlaps the window's leading edge.

**Guarantees callers may rely on**
- An event recorded at time `t` is counted iff its whole bucket starts inside the window, so the effective cutoff is quantized to bucket boundaries. The count can therefore *under*-report events sitting in the partially-overlapping oldest bucket; the error is bounded by one bucket width.
- Document that trade-off in the `@moduledoc` and tell users to pick `:bucket_ms` small relative to the smallest window they query.
- A bucket whose start time is exactly `now - window_ms` **is** included — the boundary is inclusive on the old side.
- The window is relative to `now` on every call: the same key with the same `window_ms` may return a smaller number later, purely because the clock moved.

**Unknown / empty cases**
- `count/3` returns `0` for a key that has never been incremented, and for a key whose buckets have all aged out or been cleaned up.
- It must not raise and must not create an entry for that key.
- Counting is read-only: it never mutates state, and repeated calls with an unchanged clock return the same number.

**Key isolation**
- Different keys are tracked independently: incrementing `"page:home"` must not affect `"page:about"`.
- Cleanup of one key must not disturb another.

**State shape**
- Keep counters in `state.keys` as a map of `key => %{bucket_index => count}`.
- Callers and cleanup assertions rely on `state.keys` being exactly that, and an empty map `%{}` when no data is live.

**Cleanup — memory must not leak**
- Schedule cleanup with `Process.send_after/3` sending the bare atom `:cleanup` to the process, every `:cleanup_interval_ms`. Schedule the first one during `init/1`. When `:cleanup_interval_ms` is `:infinity`, schedule nothing.
- Handle a `:cleanup` message in `handle_info/2` regardless of where it came from, so it can be sent directly to the process to force cleanup on demand.
- After handling it, re-arm the timer — again, no re-arming when the interval is `:infinity` — so a directly-sent `:cleanup` is idempotent with respect to the timer and never spawns a second timer chain.
- A cleanup pass reads the clock and drops every bucket whose start time is before `now - max_window_ms`: keep bucket `b` iff `b >= ceil((now - max_window_ms) / bucket_ms)`, the same ceiling rule used by `count/3`.
- That rule guarantees cleanup can never delete data a `count/3` call with `window_ms <= max_window_ms` would still have counted.
- When a key has no surviving buckets, remove the key from `state.keys` entirely — don't leave an empty inner map behind. If every key expires, `state.keys` becomes `%{}`.
- Cleanup with a clock that hasn't advanced past the horizon is a no-op: nothing is dropped and the state is unchanged. Running cleanup twice in a row changes nothing the second time.

**Other messages**
- Any `handle_info/2` message other than `:cleanup` is silently ignored (`{:noreply, state}`).
- A stray `send/2` from unrelated code must never crash the counter or alter its state.

**Deliverable**
- Complete module in a single file, with typespecs.
- `@moduledoc` explaining the sub-bucket design, the accuracy/bucket-width trade-off, and the cleanup contract.
