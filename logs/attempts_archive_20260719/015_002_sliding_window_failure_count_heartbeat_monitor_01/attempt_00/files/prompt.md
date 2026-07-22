# Sliding-Window Failure-Count Heartbeat Monitor

Write me an Elixir `GenServer` module called `WindowMonitor` that watches a set of
registered services by running a health *probe* for each one and deciding whether
the service is `:up` or `:down` based on **how many of its most recent probe
results were failures** — a sliding window, not a run of consecutive failures.

Use only the OTP standard library — no external dependencies. Give me the complete
module in a single file.

## Public API

- `WindowMonitor.start_link(opts \\ [])` — starts the process, linked to the caller,
  returning the usual `GenServer.on_start()` result. `opts` is a keyword list
  defaulting to `[]`. When a `:name` option is present it is used for process
  registration (so the other functions accept either the pid or the registered
  name); when absent the process starts unregistered. A freshly started server
  watches zero services.

- `WindowMonitor.watch(server, name, probe, opts \\ [])` — registers a service to
  be watched and returns `:ok`.
  - `name` is any term identifying the service (compared by value).
  - `probe` is a **zero-arity** function returning either `:ok` (healthy) or
    `{:error, reason}` (unhealthy); `reason` may be any term. Guard the public
    function with `is_function(probe, 0)`.
  - `opts` may contain:
    - `:window` — a positive integer, the number of most-recent probe results the
      server retains for this service. Defaults to `5`.
    - `:threshold` — a positive integer, the number of failures **within the
      retained window** at or above which the service is considered `:down`.
      Defaults to `3`.
    - `:on_change` — an arity-2 function called as `on_change.(name, new_status)`
      on each status transition (see below). Defaults to a no-op.
    - `:interval` — a positive integer number of milliseconds, or the atom
      `:manual` (the default). When a positive integer, the server automatically
      probes this service on that interval using `Process.send_after/3`; the first
      automatic probe fires one interval after `watch`, and probing repeats
      indefinitely. When `:manual`, the service is only probed via `probe_now/2`.
  - A newly watched service starts with status `:up` and an **empty** result
    window. Watching a `name` that already exists replaces its configuration and
    resets it to this initial state.

- `WindowMonitor.probe_now(server, name)` — runs exactly one probe for the named
  service immediately (the same work an automatic tick performs), applies the
  result, and returns `{:ok, new_status}` where `new_status` is that service's
  status after the probe. Returns `{:error, :not_found}` if `name` is not watched.

- `WindowMonitor.health(server, name)` — returns `{:ok, :up}` / `{:ok, :down}` for
  a watched service, or `{:error, :not_found}` if it was never watched.

- `WindowMonitor.report(server)` — returns a map `%{name => :up | :down}` of every
  currently watched service and its current status. Empty map `%{}` when nothing is
  watched.

## Running a probe

A single probe invokes the service's `probe` function (**synchronously inside the
server process**) and records the outcome as either a success or a failure. The
server keeps only the `:window` most-recent outcomes for the service (older ones are
discarded). After recording:

- Let `f` be the number of **failures among the retained results** (at most
  `:window` of them) and `t` be `:threshold`.
- The new status is `:down` when `f >= t`, otherwise `:up`.
- The status is recomputed from the window on **every** probe. Because the window
  slides, a service can recover automatically: once enough healthy results push
  failures out of the window so that `f < t`, it returns to `:up` — no explicit
  "success streak" is required.

Failures do **not** have to be consecutive. For example with `window: 5` and
`threshold: 3`, the sequence error, ok, error, ok, error leaves three failures in
the window and marks the service `:down`, even though no two failures were adjacent.

## Status transitions and notifications

A "transition" is any change of the status field (`:up` → `:down` or
`:down` → `:up`). On each actual change — and only then — the service's `:on_change`
function is called exactly once as `on_change.(name, new_status)` with the status
just entered. A probe that leaves the status unchanged calls nothing.

## Independence and robustness

- Services are fully independent: one service's results, window, or status never
  affect another's.
- Any message the server does not understand must be ignored: it must neither crash
  the process nor alter any service's state.