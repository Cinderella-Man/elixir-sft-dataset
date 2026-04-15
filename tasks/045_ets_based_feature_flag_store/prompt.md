Write me an Elixir module called `FeatureFlags` that manages feature flags using ETS for fast reads, backed by a GenServer for writes.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration.
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on` for everyone.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off` for everyone.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag to `:percentage` mode with a value between `0` and `100` (integers). Calling with `0` is equivalent to `:off`, and `100` is equivalent to `:on`.
- `FeatureFlags.enabled?(flag_name)` — returns `true` if the flag is `:on`, `false` otherwise (`:off` or `:percentage` flags return `false` here). Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` if the flag is `:on`, or if the flag is in `:percentage` mode and the user falls within the enabled bucket. The bucket must be **deterministic**: the same `{flag_name, user_id}` pair must always produce the same result across calls. Use `:erlang.phash2({flag_name, user_id}, 100)` to compute a 0–99 hash and compare it against the percentage threshold. If the flag is `:off`, always return `false`. Unknown flags default to `false`.

Implementation requirements:
- ETS table should be of type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly without going through the GenServer process for `enabled?` and `enabled_for?` reads.
- All writes (`enable`, `disable`, `enable_for_percentage`) must go through the GenServer via `call` to serialise updates.
- The ETS table must be created in `init/1` and the table name should be accessible via a module attribute or passed through the GenServer state.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.