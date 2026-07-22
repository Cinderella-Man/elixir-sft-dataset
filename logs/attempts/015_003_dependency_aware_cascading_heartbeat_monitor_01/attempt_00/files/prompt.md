# Dependency-Aware Cascading Heartbeat Monitor

Write me an Elixir `GenServer` module called `DepMonitor` that watches a set of
services arranged in a **dependency graph**. Each service has its own health (based
on a probe), but a service is also considered unhealthy whenever any service it
depends on (directly or transitively) is unhealthy. This models cascading outages:
when a database goes down, everything depending on it is effectively down too.

Use only the OTP standard library — no external dependencies. Give me the complete
module in a single file.

## Two kinds of status

- **Own status** (`direct_status/2`) — a node's health considering only its own
  probe results, using a consecutive-failure threshold.
- **Effective status** (`effective_status/2`) — a node is effectively `:down` when
  its own status is `:down` **or** any node it depends on is effectively `:down`;
  otherwise it is effectively `:up`. Dependencies are followed transitively. The
  dependency graph must be acyclic; behavior on a cycle is undefined.

## Public API

- `DepMonitor.start_link(opts \\ [])` — starts the process, linked to the caller,
  returning the usual `GenServer.on_start()` result. `opts` defaults to `[]`. A
  `:name` option, when present, is used for process registration (functions accept
  the pid or the registered name); otherwise the process is unregistered. A freshly
  started server has no nodes.

- `DepMonitor.add_node(server, name, probe, opts \\ [])` — adds a node and returns
  `:ok`.
  - `name` is any term identifying the node (compared by value).
  - `probe` is a **zero-arity** function returning `:ok` or `{:error, reason}`.
    Guard the public function with `is_function(probe, 0)`.
  - `opts` may contain:
    - `:depends_on` — a list of node names this node depends on. Defaults to `[]`.
      Names that are not (yet) added are treated as effectively `:up`.
    - `:threshold` — a positive integer, the number of **consecutive** own-probe
      failures required before the node's own status becomes `:down`. Defaults to
      `3`.
    - `:on_change` — an arity-2 function called as
      `on_change.(name, new_effective_status)` whenever this node's **effective**
      status changes (see below). Defaults to a no-op.
    - `:interval` — a positive integer number of milliseconds, or `:manual` (the
      default). A positive integer schedules automatic probes of *this node* on that
      interval via `Process.send_after/3`, the first firing one interval after the
      node is added; `:manual` means the node is only probed via `check/2`.
  - A newly added node starts with own status `:up` and `0` consecutive failures.
    Adding a node never invokes any `on_change` callback. Adding a `name` that
    already exists replaces its configuration and resets it to this initial state.

- `DepMonitor.check(server, name)` — runs exactly one probe for **only the named
  node** (the same work an automatic tick performs), updates that node's own status,
  and returns `{:ok, effective}` where `effective` is the named node's effective
  status afterward. Returns `{:error, :not_found}` if `name` was never added.

- `DepMonitor.direct_status(server, name)` — returns `{:ok, :up}` / `{:ok, :down}`
  for the node's **own** status, or `{:error, :not_found}`.

- `DepMonitor.effective_status(server, name)` — returns `{:ok, :up}` /
  `{:ok, :down}` for the node's **effective** status, or `{:error, :not_found}`.

- `DepMonitor.snapshot(server)` — returns a map `%{name => effective_status}` for
  every node. Empty map `%{}` when there are no nodes.

## Updating own status on a probe

A probe invokes the node's `probe` function (**synchronously inside the server
process**). Let the node have own status `st`, consecutive-failure count `c`, and
threshold `t`.

- On `:ok`: the count resets to `0`; if `st` was `:down` it becomes `:up`,
  otherwise it stays `:up`.
- On `{:error, _reason}`: the count becomes `c + 1`; if the new count is `>= t`
  **and** `st` was `:up`, own status becomes `:down`; otherwise own status is left
  unchanged. Because failures must be consecutive, any `:ok` resets the count.

## Effective-status transitions and notifications

After any probe (via `check/2` or an automatic tick), the server recomputes the
effective status of every node. For **each** node whose effective status changed as
a result — and only those — its `:on_change` callback is invoked exactly once as
`on_change.(name, new_effective_status)`.

This means a probe on one node can notify several nodes: if a dependency's own probe
takes it down, that dependency **and** every node depending on it (transitively)
change effective status and each fires its own `on_change`. Likewise, when the
dependency recovers, all of them fire again on the way back up.

## Independence and robustness

- Nodes not connected by a dependency edge never affect one another.
- Any message the server does not understand must be ignored: it must neither crash
  the process nor alter any node's state.