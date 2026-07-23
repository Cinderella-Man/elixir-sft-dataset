# Design Brief: `FeatureFlags` — a dependency-aware feature flag store

## Problem

We need a feature flag store for Elixir that serves reads at ETS speed while routing every write through a GenServer, and that supports **prerequisite dependencies** between flags.

A flag can declare that it depends on other flags: it is only considered enabled when all of its prerequisites are also enabled (evaluated transitively). This is useful for gating a feature behind a chain of rollouts.

Deliverable: the complete module, called `FeatureFlags`, in a single file.

## Constraints

- ETS table should be of type `:set` with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `enabled_for?`, `prerequisites`) — the recursive dependency evaluation happens in the calling process straight against ETS, with no GenServer round-trip.
- All writes (`enable`, `disable`, `enable_for_percentage`, `set_prerequisites`) must go through the GenServer via `call`. Cycle detection must happen in the GenServer before committing prerequisites.
- The ETS table must be created in `init/1`.
- Use only the OTP standard library, no external dependencies.

## Required interface

1. `FeatureFlags.start_link(opts)` — starts the process, returning `{:ok, pid}` on success. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). The write functions below take no server argument, so they must still reach the running process even when it is started with `name: nil` (i.e. unregistered) — track the running instance globally.
2. `FeatureFlags.enable(flag_name)` — sets the flag's own state to `:on`.
3. `FeatureFlags.disable(flag_name)` — sets the flag's own state to `:off`.
4. `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag's own state to `:percentage` mode with an integer 0–100.
5. `FeatureFlags.set_prerequisites(flag_name, prereqs)` — declares that `flag_name` requires every flag in the list `prereqs` (a list of atoms). Setting prerequisites must **not** create a cycle (including self-dependency or a transitive loop through existing prerequisites); if it would, leave the graph unchanged and return `{:error, :cycle}`. Otherwise return `:ok`. Setting prerequisites preserves the flag's own state, and setting state preserves prerequisites.
6. `FeatureFlags.prerequisites(flag_name)` — returns the flag's declared prerequisite list (or `[]`).
7. `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag's own state is `:on` **and** every prerequisite is `enabled?` (recursively). Unknown flags default to `false`.
8. `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` when the flag's own state evaluates true for that user (`:on`, or `:percentage` mode with `:erlang.phash2({flag_name, user_id}, 100) < percentage`) **and** every prerequisite is `enabled_for?/2` for the same `user_id` (recursively). `:off` and unknown flags return `false`. The bucket must be deterministic per `{flag_name, user_id}` pair.

## Acceptance criteria

- All eight public functions above exist with the stated arities and return values.
- Enabling/disabling and percentage rollout are settable independently of prerequisites, and neither operation clobbers the other.
- Cycle-creating calls to `set_prerequisites/2` return `{:error, :cycle}` and leave the prerequisite graph untouched; all other calls return `:ok`.
- `enabled?/1` and `enabled_for?/2` resolve prerequisite chains transitively and return `false` for unknown flags.
- Repeated `enabled_for?/2` calls for the same `{flag_name, user_id}` pair yield the same result.
- Reads hit the named ETS table directly from the caller; writes are GenServer `call`s.
- Works when started with `name: nil`.
