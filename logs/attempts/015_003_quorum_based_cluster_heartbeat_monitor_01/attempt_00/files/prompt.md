# Quorum-Based Cluster Heartbeat Monitor

Write me an Elixir module called `ClusterMonitor` — a `GenServer` that supervises a
set of registered **clusters**, where each cluster is a group of independent
endpoints, and decides the cluster's `:up`/`:down` status by **quorum**: the cluster
is `:up` when at least a configured number of its endpoints report healthy on a
single poll. Use only the OTP standard library, no external dependencies, and give me
the complete module in a single file.

Unlike a consecutive-failure monitor, the status here is recomputed **fresh** on
every poll from the current health of all endpoints — there is no running
consecutive-failure counter.

## The singleton and its lifecycle

`ClusterMonitor` is a singleton process. The convenience functions below
(`register_cluster`, `poll`, `cluster_state`, `snapshot`, `unregister`) take **no
server argument** — they operate on the process registered under the module name
`ClusterMonitor`.

- `ClusterMonitor.start_link(opts \\ [])` starts and links the process and returns
  the usual `GenServer.on_start()` result. `opts` is a keyword list defaulting to
  `[]`. The process must be registered under the name `ClusterMonitor` (i.e.
  `__MODULE__`) so the no-argument convenience API can find it. A `:name` option may
  override the registered name, but the convenience functions always target
  `ClusterMonitor`.
- Starting the server does no monitoring work; a freshly started server tracks zero
  clusters, and `ClusterMonitor.snapshot()` returns `%{}`.

## Registering clusters

`ClusterMonitor.register_cluster(name, check_funcs, interval_ms, opts \\ [])`

- `name` is any term used as the key (strings, atoms, tuples all work and are
  compared by value).
- `check_funcs` is a **non-empty list** of **zero-arity** endpoint functions, each
  returning either `:ok` (that endpoint is healthy) or `{:error, reason}` (that
  endpoint is unhealthy). The number of functions is the cluster's `total`.
- `interval_ms` is a **positive integer**: how often, in milliseconds, the monitor
  polls the whole cluster after registration.
- `opts` is a keyword list:
  - `:quorum` — a **positive integer** `Q`: the cluster is `:up` when at least `Q`
    endpoints are healthy on a poll. Defaults to a strict majority,
    `div(total, 2) + 1`.
  - `:notify` — a **two-arity** function `notify.(name, healthy_count)` invoked when
    the cluster transitions from `:up` to `:down` (see below). Defaults to a no-op.

`register_cluster/4` returns `:ok`.

Guards: `check_funcs` must be a non-empty list, `interval_ms` must be a positive
integer, and every element of `check_funcs` must be a zero-arity function. Violating
any of these is outside the contract and raises `FunctionClauseError`; guard the
public function accordingly.

On registration:

- The cluster's status starts as `:up`, and until the first poll runs,
  `cluster_state/1` reports `healthy` equal to `total`.
- Registration itself does **not** poll. The first poll happens one `interval_ms`
  later, then repeats every `interval_ms` thereafter (implemented with
  `Process.send_after/3`, re-scheduling itself after each poll).

Re-registering an already-registered `name` **replaces** its configuration (endpoint
functions, interval, quorum, notify) and **resets** its status to `:up` with
`healthy` equal to the new `total`.

### Lifecycle rule for re-registration (important)

When a cluster is re-registered, the **previous registration's scheduled polls must
never run again**. After a re-registration:

- The old endpoint functions are never called again by any leftover/previously-
  scheduled timer.
- Polls for that cluster happen only at the **new** interval, calling the **new**
  endpoint functions.

Superseded timer chains are dead. (A robust way to achieve this is to tag each
registration with a generation token and ignore scheduled poll messages whose token
no longer matches the current registration.)

## Performing a poll

Each poll — whether triggered by the periodic timer or by `poll/1` below — does
exactly the following:

- Calls **every** endpoint function once.
- Computes `healthy` = the number of endpoints that returned `:ok`.
- Sets the new status to `:up` if `healthy` is greater than or equal to `quorum`,
  otherwise `:down`.
- If the status transitions from `:up` to `:down` on this poll, the notify function
  is called **exactly once** as `notify.(name, healthy)`, with the `healthy` count
  from this poll.
- A transition from `:down` to `:up` (recovery) does **not** call the notify
  function. A poll that finds the cluster already `:down` and still `:down` does
  **not** call notify again.

The recorded `healthy` and `total` are updated to reflect this poll.

## Deterministic single poll

`ClusterMonitor.poll(name)` synchronously performs **one** poll for the named cluster
immediately — identical work to a scheduled interval tick (calling every endpoint,
recomputing `healthy`/status, and firing notify on an `:up` -> `:down` transition).
It returns `{:ok, status}` where `status` is the resulting status (`:up` or
`:down`), or `{:error, :not_found}` if no such cluster is registered. `poll/1` does
not alter or reschedule the periodic timer.

## Querying and removing

- `ClusterMonitor.cluster_state(name)` returns a map
  `%{status: :up | :down, healthy: non_neg_integer(), total: pos_integer()}` for a
  registered cluster, or `{:error, :not_found}` if the cluster is unknown.
- `ClusterMonitor.snapshot()` returns a map `%{name => status}` containing every
  currently registered cluster and its `:up`/`:down` status. With no clusters
  registered it returns `%{}`.
- `ClusterMonitor.unregister(name)` removes a cluster. It returns `:ok` if the
  cluster existed (after removal it no longer appears in `snapshot/0` and
  `cluster_state/1` returns `{:error, :not_found}`), or `{:error, :not_found}` if no
  such cluster was registered. After removal the cluster's scheduled polls must never
  run again — its timer chain is dead.

## Robustness

Any unexpected message sent to the server (anything other than the messages it uses
for its own scheduling) must be ignored: it must not crash the process or alter
state.

Clusters are fully independent: polling one cluster never affects another cluster's
status, `healthy`, or `total`.