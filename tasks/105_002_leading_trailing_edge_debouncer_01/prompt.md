# EdgeDebouncer — a GenServer debouncer with leading / trailing / both edges

Write me an Elixir module called `EdgeDebouncer`, implemented as a `GenServer`,
that debounces function calls on a per-key basis with a configurable **firing
edge** — the classic trailing-edge debounce, a leading-edge debounce that fires
immediately, or **both** edges (fire on the way in *and* on the way out of a
burst). This mirrors the `leading`/`trailing` options you find in libraries like
lodash's `debounce`.

## Public API

- `EdgeDebouncer.start_link(opts)` — starts the process. It should accept a
  `:name` option for process registration, defaulting to `EdgeDebouncer` (the
  module name) when not provided. Return the usual `{:ok, pid}`.

- `EdgeDebouncer.call(key, delay_ms, func, opts \\ [])` — schedules/handles
  `func` (a zero-arity function) for `key`. `opts` accepts `:edge`, one of
  `:trailing` (default), `:leading`, or `:both`. `key` can be any term. This
  function must return `:ok` and return promptly (it must never block waiting for
  `func` to run). It targets the default registered process (registered under the
  name `EdgeDebouncer`). An invalid `:edge` value should raise `ArgumentError`.

## Edge semantics

A **burst** for a key begins with a `call/4` when that key has no pending timer,
and ends when `delay_ms` elapses with no further calls for that key. Within a
burst each new `call/4` resets the timer (restart from `delay_ms`) and replaces
the pending trailing `func`. The edge is determined by the **first** call that
opens the burst.

- **`:trailing`** — nothing runs on the way in; when the burst settles, only the
  most recently supplied `func` runs, exactly once. (Same behavior as a plain
  debouncer.)

- **`:leading`** — the first call's `func` runs **immediately**. All later calls
  in the burst are coalesced away and never run — no trailing execution occurs.

- **`:both`** — the first call's `func` runs immediately (leading). If — and only
  if — at least one *additional* call arrived during the burst, the most recently
  supplied `func` also runs once when the burst settles (trailing). A burst
  consisting of a single call fires leading only (never twice).

Other rules:

- **The delay is real.** Trailing executions must not run before `delay_ms` has
  elapsed since the most recent `call/4` for that key.
- **Keys are independent.** A pending debounce on one key must not affect another.
- **State is cleared after firing.** Once a burst settles, the key's state is
  gone; a subsequent `call/4` starts a brand-new burst (leading fires again).

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending.
- Run `func` off the server's reduction path (e.g. in a spawned process) so a
  slow or crashing `func` can't wedge the GenServer.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.