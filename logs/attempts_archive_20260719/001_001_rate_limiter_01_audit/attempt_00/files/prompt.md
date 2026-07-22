Write me an Elixir GenServer module called `RateLimiter` that enforces per-key rate limits using a sliding window algorithm.

I need these functions in the public API:

- `RateLimiter.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `RateLimiter.check(server, key, max_requests, window_ms)` which checks whether a request for the given key is allowed. If allowed, return `{:ok, remaining}` where remaining is how many more requests are available in the current window. If not allowed, return `{:error, :rate_limited, retry_after_ms}` where retry_after_ms tells the caller how long to wait.

Each key must be tracked independently — rate limiting "user:1" should have no effect on "user:2". The sliding window should work correctly at boundaries, meaning if I make 3 requests allowed per 1000ms window and I make them at time 0, then at time 1001 I should be allowed again.

You also need to make sure expired entries get cleaned up so the GenServer doesn't leak memory over time. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any tracking data for windows that have fully expired.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## Startup contract

- `start_link/1` links the new process to the caller and returns the usual
  `GenServer.on_start()` result. The `opts` argument is a keyword list and should
  default to `[]` when omitted.
- When `:name` is given it is used for process registration (so `check/4` can be
  called with either the pid or the registered name). When `:name` is absent the
  process is started unregistered. `:name` must not be passed through as part of
  the server's own configuration — it is purely a registration concern.
- `:clock` defaults to `fn -> System.monotonic_time(:millisecond) end`. Every time
  the server needs "now" — on a `check/4` and on a cleanup pass — it calls the
  configured clock function afresh. A test clock returning a fixed integer must
  therefore make time appear frozen, and a clock the caller mutates must be
  observed at its current value on the next call.
- `:cleanup_interval_ms` defaults to `60_000`.
- Starting the server performs no work other than setting up state and, if
  applicable, scheduling the first cleanup. In particular a freshly started server
  tracks zero keys.

## `check/4` contract

`check/4` is a synchronous call. It takes a `key` (any term — strings, atoms,
tuples, integers all work and are compared by value), a positive integer
`max_requests`, and a positive integer `window_ms`. Calling it with a non-integer
or non-positive `max_requests`/`window_ms` is outside the contract and may raise
a `FunctionClauseError` — guard the public function accordingly. The `key` is not
validated.

Semantics of a single call, at time `now` returned by the clock:

1. The timestamps already recorded for `key` are pruned: a timestamp is **active**
   iff `ts > now - window_ms`. So an entry recorded exactly `window_ms`
   milliseconds ago is *not* active — it has just fallen out of the window. An
   entry recorded `window_ms - 1` ms ago is still active.
2. Let `count` be the number of active timestamps.
   - If `count < max_requests`, the request is **allowed**: `now` is recorded as a
     new timestamp for `key`, and the reply is `{:ok, remaining}` where
     `remaining = max_requests - count - 1`. So the first call under a limit of 5
     returns `{:ok, 4}`, then `{:ok, 3}`, … and the last allowed call returns
     `{:ok, 0}`.
   - If `count >= max_requests`, the request is **denied** and the reply is
     `{:error, :rate_limited, retry_after_ms}`. A denied call does **not** record a
     timestamp — being rate limited never pushes the window forward, so repeatedly
     hammering a limited key does not extend the block.
3. `retry_after_ms` is computed from the **oldest** active timestamp `oldest`:
   `retry_after_ms = max(oldest + window_ms - now, 1)`. It is therefore always at
   least `1` and never `0` or negative, and it is the minimum wait after which the
   oldest tracked request drops out of the window and a slot frees up. Waiting
   exactly `retry_after_ms` and calling again must succeed (given no other calls in
   between).

Additional observable properties:

- Pruning happens on denied calls too: the stored timestamp list for the key is
  replaced with the pruned (active-only) list even when the reply is an error. A
  caller cannot observe this directly except through subsequent `check/4` results,
  which must remain consistent with the rules above.
- Boundary example that must hold: with `max_requests = 3`, `window_ms = 1000`,
  three calls at time `0` return `{:ok, 2}`, `{:ok, 1}`, `{:ok, 0}`; a fourth call
  at time `0` returns `{:error, :rate_limited, 1000}`; a call at time `1000`
  succeeds (the time-0 entries are no longer active, since `0 > 1000 - 1000` is
  false), and a call at `1001` likewise succeeds.
- Keys are fully independent: exhausting the limit for one key never affects the
  result for any other key, and an unknown/never-seen key behaves exactly like a
  key with zero active timestamps (first call returns `{:ok, max_requests - 1}`).
- `max_requests` and `window_ms` are supplied per call, not fixed at startup. The
  same key may be checked with different limits over time; the effective window
  for pruning is always the `window_ms` passed to the current call, and the
  `window_ms` most recently seen for a key is what a cleanup pass uses for that key.
- Two calls at the same clock value are both recorded; identical timestamps are
  allowed and each counts separately toward the limit.

## Cleanup contract

- Unless the interval is `:infinity`, the server schedules a `:cleanup` message to
  itself via `Process.send_after/3` at startup and re-schedules the next one at the
  end of each cleanup pass, so the sweep repeats indefinitely.
- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the
  periodic timer is never scheduled — nothing runs automatically. The server is
  otherwise fully functional; only the automatic sweep is disabled.
- Sending the server process a bare `:cleanup` message performs one cleanup pass
  immediately — the same work the periodic timer performs. This is how a caller can
  deterministically trigger a sweep with a test clock. (Note: a manually sent
  `:cleanup` also re-schedules the next timer when the interval is an integer.)
- A cleanup pass reads the clock once and, for every tracked key, prunes timestamps
  using the same "active" rule (`ts > now - window_ms`, with that key's most
  recently seen `window_ms`). A key whose active list becomes empty is **removed
  entirely** from the server's state; keys with at least one active timestamp are
  retained with their pruned list. Cleanup never changes whether a subsequent
  `check/4` is allowed — it is purely a memory reclamation pass, and running it any
  number of times (including on an empty state) is idempotent and side-effect free
  from the caller's point of view.
- The server must tolerate arbitrary unexpected messages: any message other than
  `:cleanup` is ignored and must not crash the process or alter state.
