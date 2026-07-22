# Escalating Severity-Level Health Monitor

Write me an Elixir module called `HealthMonitor` — a `GenServer` that supervises a
set of registered *probes* by calling a check function for each one on a periodic
interval, tracking each probe's **severity level**, and firing a callback whenever a
probe's level changes. Use only the OTP standard library, no external dependencies,
and give me the complete module in a single file.

Unlike a plain up/down monitor, each probe has **three** severity levels —
`:ok`, `:warning`, and `:critical` — driven by how many checks have failed in a row.

## The singleton and its lifecycle

`HealthMonitor` is a singleton process. The convenience functions below
(`add_probe`, `level`, `report`, `probe_now`, `remove_probe`) take **no server
argument** — they operate on the process registered under the module name
`HealthMonitor`.

- `HealthMonitor.start_link(opts \\ [])` starts and links the process and returns
  the usual `GenServer.on_start()` result. `opts` is a keyword list defaulting to
  `[]`. The process must be registered under the name `HealthMonitor` (i.e.
  `__MODULE__`) so the no-argument convenience API can find it. A `:name` option may
  override the registered name, but the convenience functions always target
  `HealthMonitor`.
- Starting the server does no monitoring work; a freshly started server tracks zero
  probes, and `HealthMonitor.report()` returns `%{}`.

## Registering probes

`HealthMonitor.add_probe(name, check_func, interval_ms, opts \\ [])`

- `name` is any term used as the key (strings, atoms, tuples all work and are
  compared by value).
- `check_func` is a **zero-arity** function returning either `:ok` (healthy) or
  `{:error, reason}` (unhealthy), where `reason` is any term.
- `interval_ms` is a **positive integer**: how often, in milliseconds, the monitor
  calls `check_func` after registration.
- `opts` is a keyword list:
  - `:warn_after` — a **positive integer** `W`; defaults to `2`.
  - `:crit_after` — a **positive integer** `C`; defaults to `4`.
  - `:on_change` — a **four-arity** function
    `on_change.(name, old_level, new_level, reason)` invoked whenever the probe's
    level changes (see below). Defaults to a no-op.

`add_probe/4` returns `:ok`.

Guards: `check_func` must be a zero-arity function and `interval_ms` must be a
positive integer. Calling `add_probe` with a non-positive or non-integer
`interval_ms`, or a check function of the wrong arity, is outside the contract and
raises `FunctionClauseError`; guard the public function accordingly.

On registration:

- The probe's level starts as `:ok` with a consecutive-failure count of `0`.
- Registration itself does **not** run the check function. The first check happens
  one `interval_ms` later, then repeats every `interval_ms` thereafter (implemented
  with `Process.send_after/3`, re-scheduling itself after each check).

Re-adding an already-registered `name` **replaces** its configuration (check
function, interval, thresholds, on_change) and **resets** its level to `:ok` with a
failure count of `0`.

### Lifecycle rule for re-adding (important)

When a probe is re-added, the **previous registration's scheduled checks must never
run again**. After a re-add:

- The old check function is never called again by any leftover/previously-scheduled
  timer.
- Checks for that probe happen only at the **new** interval, calling the **new**
  check function.

Superseded timer chains are dead. (A robust way to achieve this is to tag each
registration with a generation token and ignore scheduled check messages whose token
no longer matches the current registration.)

## Performing a check

Each check — whether triggered by the periodic timer or by `probe_now/1` below —
calls `check_func.()` exactly once and then updates the probe:

- If the result is `:ok`: the consecutive-failure count is reset to `0` and the new
  level is `:ok`.
- If the result is `{:error, reason}`: the consecutive-failure count is incremented
  by one. The new level is then determined **solely** by the resulting count:
  - `:critical` if the count is greater than or equal to `crit_after`;
  - otherwise `:warning` if the count is greater than or equal to `warn_after`;
  - otherwise `:ok`.

After computing the new level, if (and only if) it **differs** from the probe's
previous level, the `on_change` callback is invoked **exactly once** as
`on_change.(name, old_level, new_level, reason)`, where:

- on an escalation caused by a failing check, `reason` is the reason returned by
  **that** failing check;
- on a recovery to `:ok` caused by a successful check, `reason` is `nil`.

If the new level equals the previous level, `on_change` is **not** called.

"Consecutive" means any `:ok` result resets the counter to zero, so a probe that
recovers and later fails again escalates again from scratch.

## Deterministic single check

`HealthMonitor.probe_now(name)` synchronously performs **one** check for the named
probe immediately — identical work to a scheduled interval tick (calling the check
function, updating the failure count and level, and firing `on_change` on a level
change). It returns `{:ok, level}` where `level` is the resulting level (`:ok`,
`:warning`, or `:critical`), or `{:error, :not_found}` if no such probe is
registered. `probe_now/1` does not alter or reschedule the periodic timer.

## Querying and removing

- `HealthMonitor.level(name)` returns `:ok`, `:warning`, or `:critical` for a
  registered probe, or `{:error, :not_found}` if the probe is unknown.
- `HealthMonitor.report()` returns a map `%{name => level}` containing every
  currently registered probe and its level. With no probes registered it returns
  `%{}`.
- `HealthMonitor.remove_probe(name)` removes a probe. It returns `:ok` if the probe
  existed (after removal it no longer appears in `report/0` and `level/1` returns
  `{:error, :not_found}`), or `{:error, :not_found}` if no such probe was registered.
  After removal the probe's scheduled checks must never run again — its timer chain
  is dead.

## Robustness

Any unexpected message sent to the server (anything other than the messages it uses
for its own scheduling) must be ignored: it must not crash the process or alter
state.

Probes are fully independent: escalating one probe never affects another probe's
level or failure count.