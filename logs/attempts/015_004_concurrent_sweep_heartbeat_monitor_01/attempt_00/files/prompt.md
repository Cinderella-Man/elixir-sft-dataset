# Concurrent Sweep Heartbeat Monitor

Write me an Elixir `GenServer` module called `AsyncMonitor` that watches a set of
enrolled services and probes them **concurrently**. Unlike a monitor that runs each
probe synchronously inside the server, this one dispatches every service's probe to
its **own separate process** so that slow probes cannot block one another, and a
"sweep" gathers the results.

Use only the OTP standard library — no external dependencies. Give me the complete
module in a single file.

## Public API

- `AsyncMonitor.start_link(opts \\ [])` — starts the process, linked to the caller,
  returning the usual `GenServer.on_start()` result. `opts` defaults to `[]`. A
  `:name` option, when present, is used for process registration (functions accept
  the pid or the registered name); otherwise the process is unregistered. A freshly
  started server has zero enrolled services.

- `AsyncMonitor.enroll(server, name, probe, opts \\ [])` — enrolls a service and
  returns `:ok`.
  - `name` is any term identifying the service (compared by value).
  - `probe` is a **zero-arity** function returning `:ok` or `{:error, reason}`.
    Guard the public function with `is_function(probe, 0)`.
  - `opts` may contain:
    - `:threshold` — a positive integer, the number of **consecutive** failed
      probes required before the service is marked `:down`. Defaults to `3`.
    - `:on_change` — an arity-2 function called as `on_change.(name, new_status)`
      on each status transition (see below). Defaults to a no-op.
  - A newly enrolled service starts with status `:up` and `0` consecutive failures.
    Enrolling a `name` that already exists replaces its configuration and resets it
    to this initial state.

- `AsyncMonitor.sweep(server)` — runs **one probe for every currently enrolled
  service**. Each service's probe is invoked in its own separate process, and all
  the probes of a single sweep run **concurrently** (one probe process per service,
  all launched before any of them needs to finish). `sweep/1` **blocks** and returns
  `:ok` only after every probe in the sweep has finished and its result has been
  applied to that service's status. If no services are enrolled, `sweep/1` returns
  `:ok` immediately.

- `AsyncMonitor.status(server, name)` — returns `{:ok, :up}` / `{:ok, :down}` for an
  enrolled service, or `{:error, :not_found}` if it was never enrolled.

- `AsyncMonitor.overview(server)` — returns a map `%{name => :up | :down}` for every
  enrolled service. Empty map `%{}` when nothing is enrolled.

## Applying a probe result

For each probe run in a sweep, the result updates that service's status. Let the
service have status `st`, consecutive-failure count `c`, and threshold `t`.

- If the probe returns `:ok`: the count resets to `0`; if `st` was `:down` it
  becomes `:up`, otherwise it stays `:up`.
- If the probe returns `{:error, _reason}`: the count becomes `c + 1`; if the new
  count is `>= t` **and** `st` was `:up`, the status becomes `:down`; otherwise the
  status is left unchanged. Because failures must be consecutive, any `:ok` result
  resets the count.
- If a probe **raises or throws**, it is treated as a failure (equivalent to an
  `{:error, _}` result) and must not crash the server.

## Status transitions and notifications

A "transition" is any change of the status field (`:up` → `:down` or
`:down` → `:up`). On each actual change — and only then — the service's `:on_change`
callback is invoked exactly once as `on_change.(name, new_status)` with the status
just entered. A probe that leaves the status unchanged calls nothing.

## Concurrency, independence, and robustness

- Within a sweep, every service is probed in a distinct process, and those processes
  are all started before the sweep waits for any of them; a probe that blocks does
  not prevent the other services' probes from being invoked.
- Services are fully independent: one service's result or status never affects
  another's.
- Any message the server does not understand must be ignored: it must neither crash
  the process nor alter any service's state.