Write me an Elixir GenServer module called `ReplayEventBus` that implements an in-process pub/sub event system where new subscribers can optionally receive the **last N events** published on a topic before starting to receive live events.

The motivation: in many systems a subscriber that joins mid-stream needs to catch up on what it missed — a state-sync layer needs the most recent snapshot, a late-arriving monitor needs to see recent errors. Standard pub/sub forces every subscriber to bootstrap from an external snapshot. This module gives the bus itself a bounded per-topic history.

I need these functions in the public API:

- `ReplayEventBus.start_link(opts)` accepts:
  - `:name` — optional process registration
  - `:default_history_size` — how many events to retain per topic by default (default `100`)
  - `:history_ttl_ms` — how long events are retained, in ms (default `3_600_000`, i.e. 1 hour). Events older than this are dropped lazily on publish and during the periodic cleanup sweep.
  - `:clock` — zero-arity function returning monotonic time in ms (default `fn -> System.monotonic_time(:millisecond) end`). Used for TTL math.
  - `:cleanup_interval_ms` — periodic sweep interval in ms (default `60_000`). Setting it to `:infinity` disables auto-cleanup (useful for testing).

- `ReplayEventBus.subscribe(server, topic, pid, opts \\ [])` subscribes `pid` to the exact topic (no wildcards). `opts` may contain `:replay` with values:
  - `:none` (default) — no replay, only live events from this point forward
  - `:all` — replay every retained event for this topic, then live events
  - positive integer `n` — replay the most recent `n` retained events, then live events

  Replayed events are sent **before** `subscribe/4` returns, in oldest-to-newest order, so the subscriber sees history in chronological order. The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}`.

- `ReplayEventBus.unsubscribe(server, topic, ref)` removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.

- `ReplayEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every live subscriber (exact topic match only) AND appends the event to the topic's bounded history. History enforces two independent bounds:
  - Count bound: keep at most `history_size_for(topic)` most recent events
  - TTL bound: drop events older than `history_ttl_ms`

  Both bounds are enforced on every publish. Returns `:ok`.

- `ReplayEventBus.history(server, topic)` — returns a list of retained events for the topic in oldest-to-newest order, after applying the TTL (so stale events are not returned). Returns `[]` for unknown topics. Used mostly for debugging / inspection.

- `ReplayEventBus.set_history_size(server, topic, size)` — override the per-topic history size. `size` must be a non-negative integer; `0` disables history for that topic (existing entries are dropped). Returns `:ok`.

**Important semantics for replay-then-live**: replay must be atomic with the subscription becoming active. That is, between the last replayed event and the first live event the subscriber sees, no event can be missed or duplicated. Concretely:

1. Acquire a snapshot of the topic's history (after TTL eviction).
2. Select the last N events (or all, based on the replay option).
3. Send each historical event to the subscriber in order via `send/2`.
4. Register the subscriber in the topics map so future `publish/3` calls will deliver live events.

Because the whole subscribe handler runs inside a single GenServer call, steps 1–4 are atomic with respect to other publishes — an in-flight publish either precedes the replay (gets into history, so the subscriber sees it in step 3) or follows registration (delivered live in step 4). There's no window for missed or duplicated delivery, but a subscriber that subscribes *during* a publish might see the event twice in the worst case (once in replay, once live) — actually no: the subscribe call is serialized by the GenServer, so it either runs to completion before the publish starts or after it finishes.

Events are sent to subscribers in the shape `{:event, topic, event}` (same shape for replay and live — the subscriber can't distinguish them from the message alone).

When a monitored subscriber dies (`:DOWN` message), remove all its subscriptions across all topics. Do not purge the topic's history — history is per-topic, not per-subscriber.

Periodic cleanup via `Process.send_after(self(), :cleanup, cleanup_interval_ms)` evicts events older than the TTL across all topics. Topics whose history becomes empty AND who have zero subscribers are dropped entirely (indistinguishable from a never-seen topic).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.