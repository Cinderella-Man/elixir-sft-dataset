# `RateLimiter` — per-key sliding-window rate limiter (GenServer)

Implement an Elixir GenServer module `RateLimiter` enforcing per-key rate limits via a sliding-window algorithm. Complete module, single file, OTP standard library only, no external dependencies.

**Public API**

- `RateLimiter.start_link(opts)` — start the process.
- `RateLimiter.check(server, key, max_requests, window_ms)` — check whether a request for `key` is allowed. Allowed → `{:ok, remaining}` (`remaining` = how many more requests are available in the current window). Denied → `{:error, :rate_limited, retry_after_ms}` (`retry_after_ms` = how long to wait).

**General requirements**

- Each key tracked independently — rate limiting `"user:1"` has no effect on `"user:2"`.
- Sliding window correct at boundaries: with 3 requests per 1000ms window, requests at time 0, then at time 1001 allowed again.
- Clean up expired entries so the GenServer does not leak memory over time. Periodic cleanup via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms`) removing tracking data for fully-expired windows.

**Startup contract**

- `start_link/1` links the new process to the caller and returns the usual `GenServer.on_start()` result. `opts` is a keyword list, defaulting to `[]` when omitted.
- `:clock` option — zero-arity function returning current time in milliseconds. Defaults to `fn -> System.monotonic_time(:millisecond) end`. Every time the server needs "now" — on a `check/4` and on a cleanup pass — it calls the configured clock afresh. A test clock returning a fixed integer makes time appear frozen; a clock the caller mutates is observed at its current value on the next call.
- `:name` option — used for process registration (so `check/4` can be called with either the pid or the registered name). When `:name` is absent the process is started unregistered. `:name` must NOT be passed through as part of the server's own configuration — it is purely a registration concern.
- `:cleanup_interval_ms` defaults to `60_000`.
- Starting the server performs no work other than setting up state and, if applicable, scheduling the first cleanup. A freshly started server tracks zero keys.

**`check/4` contract**

- Synchronous call. Takes `key` (any term — strings, atoms, tuples, integers all work, compared by value), a positive integer `max_requests`, and a positive integer `window_ms`.
- A non-integer or non-positive `max_requests`/`window_ms` is outside the contract and may raise a `FunctionClauseError` — guard the public function accordingly. `key` is not validated.
- Semantics of a single call, at time `now` returned by the clock:
  1. Prune recorded timestamps for `key`: a timestamp is **active** iff `ts > now - window_ms`. An entry recorded exactly `window_ms` ms ago is NOT active (just fell out of the window); an entry recorded `window_ms - 1` ms ago is still active.
  2. Let `count` be the number of active timestamps.
     - `count < max_requests` → **allowed**: record `now` as a new timestamp for `key`; reply `{:ok, remaining}` where `remaining = max_requests - count - 1`. First call under a limit of 5 returns `{:ok, 4}`, then `{:ok, 3}`, …, last allowed call returns `{:ok, 0}`.
     - `count >= max_requests` → **denied**: reply `{:error, :rate_limited, retry_after_ms}`. A denied call does NOT record a timestamp — being rate limited never pushes the window forward, so hammering a limited key does not extend the block.
  3. `retry_after_ms` computed from the **oldest** active timestamp `oldest`: `retry_after_ms = max(oldest + window_ms - now, 1)`. Always at least `1`, never `0` or negative; it is the minimum wait after which the oldest tracked request drops out of the window and a slot frees up. Waiting exactly `retry_after_ms` and calling again must succeed (given no other calls in between).

**`check/4` observable properties**

- Pruning happens on denied calls too: the stored timestamp list for the key is replaced with the pruned (active-only) list even when the reply is an error. Not directly observable except through subsequent `check/4` results, which must stay consistent with the rules above.
- Boundary example that must hold: with `max_requests = 3`, `window_ms = 1000`, three calls at time `0` return `{:ok, 2}`, `{:ok, 1}`, `{:ok, 0}`; a fourth call at time `0` returns `{:error, :rate_limited, 1000}`; a call at time `1000` succeeds (time-0 entries no longer active, since `0 > 1000 - 1000` is false); a call at `1001` likewise succeeds.
- Keys fully independent: exhausting the limit for one key never affects any other key; an unknown/never-seen key behaves exactly like a key with zero active timestamps (first call returns `{:ok, max_requests - 1}`).
- `max_requests` and `window_ms` are supplied per call, not fixed at startup. The same key may be checked with different limits over time; the effective window for pruning is always the `window_ms` passed to the current call, and the `window_ms` most recently seen for a key is what a cleanup pass uses for that key.
- Two calls at the same clock value are both recorded; identical timestamps are allowed and each counts separately toward the limit.

**Cleanup contract**

- Unless the interval is `:infinity`, the server schedules a `:cleanup` message to itself via `Process.send_after/3` at startup and re-schedules the next one at the end of each cleanup pass, so the sweep repeats indefinitely.
- `:cleanup_interval_ms` may also be `:infinity` — then the periodic timer is never scheduled; nothing runs automatically. The server is otherwise fully functional; only the automatic sweep is disabled.
- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs. This is how a caller deterministically triggers a sweep with a test clock. A manually sent `:cleanup` also re-schedules the next timer when the interval is an integer.
- A cleanup pass reads the clock once and, for every tracked key, prunes timestamps using the same "active" rule (`ts > now - window_ms`, with that key's most recently seen `window_ms`). A key whose active list becomes empty is **removed entirely** from state; keys with at least one active timestamp are retained with their pruned list. Cleanup never changes whether a subsequent `check/4` is allowed — it is purely memory reclamation, idempotent and side-effect free from the caller's point of view, running it any number of times (including on an empty state).
- The server must tolerate arbitrary unexpected messages: any message other than `:cleanup` is ignored and must not crash the process or alter state.
