Write me an Elixir module called `FeatureFlags` that manages feature flags using ETS for fast reads, backed by a GenServer for writes, with **full change history and rollback** (an audit log).

Every write records a new immutable version, so you can inspect how a flag evolved and revert it.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the primary ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). You may create a second ETS table for history (e.g. named after `table_name`).
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on`.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off`.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets `:percentage` mode with an integer 0–100.
- `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag is `:on`. Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` if the flag is `:on`, or if it is in `:percentage` mode and `:erlang.phash2({flag_name, user_id}, 100) < percentage`. `:off` and unknown flags return `false`. The bucket must be deterministic per `{flag_name, user_id}` pair.
- `FeatureFlags.version(flag_name)` — returns the current integer version. The first write produces version `1`; every subsequent write increments it. Unknown flags return `0`.
- `FeatureFlags.history(flag_name)` — returns a list of `{version, state}` tuples in **ascending version order**, where `state` is `{:on}`, `{:off}`, or `{:percentage, n}`. Unknown flags return `[]`.
- `FeatureFlags.rollback(flag_name)` — reverts the flag to its **immediately preceding** state. Rollback is append-only: it writes the previous state as a brand-new version (so the history grows). Returns `:ok` on success, `{:error, :no_previous_version}` if the flag has only one version, and `{:error, :unknown_flag}` if the flag was never set.

Implementation requirements:
- The primary ETS table should be of type `:set` with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `enabled_for?`, `version`, `history`) without a GenServer round-trip.
- All state-changing operations (`enable`, `disable`, `enable_for_percentage`, `rollback`) must go through the GenServer via `call` to serialise updates and keep version numbers consistent.
- ETS tables must be created in `init/1`.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.