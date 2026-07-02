# Debouncer — a GenServer that coalesces rapid calls

Write me an Elixir module called `Debouncer`, implemented as a `GenServer`, that
debounces function calls on a per-key basis. This is the kind of thing you'd use
to coalesce a burst of rapid writes (autosave, search-as-you-type, config reloads)
into a single execution.

## Public API

- `Debouncer.start_link(opts)` — starts the process. It should accept a `:name`
  option for process registration, defaulting to `Debouncer` (i.e. the module
  name) when not provided. Return the usual `{:ok, pid}`.

- `Debouncer.call(key, delay_ms, func)` — schedules `func` (a zero-arity function)
  to run after `delay_ms` milliseconds. `key` can be any term. `func` is a
  zero-arity closure whose only significance to the debouncer is that it gets
  invoked. This function should return `:ok` and return promptly (it must not
  block waiting for `func` to run). It targets the default registered process
  (the one registered under the name `Debouncer`).

## Debounce semantics

- **Coalescing.** If `call/3` is invoked again with the **same key** before the
  pending timer for that key fires, the timer is reset (restarted from
  `delay_ms`) and the newly supplied `func` **replaces** the previously pending
  one. When the burst finally settles (i.e. `delay_ms` elapses with no further
  calls for that key), **only the most recently supplied `func` for that key
  runs, and it runs exactly once.** The earlier funcs from that burst are never
  executed.

- **The delay is real.** `func` must not run before `delay_ms` has elapsed since
  the most recent `call/3` for that key.

- **Keys are independent.** A pending debounce on one key must have no effect on
  any other key. Calls for different keys each get their own independent timer
  and each fire on their own schedule.

- **State is cleared after firing.** Once a key's `func` has executed, that key's
  pending state is gone. A subsequent `call/3` for the same key (after the
  previous one already fired) starts a brand-new debounce cycle and will execute
  again.

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending.
- Consider running `func` outside the server's own reduction path (e.g. in a
  spawned process) so a slow or crashing `func` can't wedge the GenServer, but
  this is your call as long as the observable semantics above hold.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.