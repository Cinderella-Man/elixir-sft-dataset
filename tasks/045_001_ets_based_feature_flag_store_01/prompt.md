**Summary:** Implement `FeatureFlags` — an Elixir module for feature-flag management with ETS-backed fast reads and a GenServer serialising writes. Single file, OTP standard library only, no external dependencies.

**Startup — `FeatureFlags.start_link(opts)`**
- Starts the process.
- Accepts optional `:table_name` for the ETS table; default `:feature_flags`.
- Accepts optional `:name` for process registration; default `FeatureFlags`. Pass `nil` to skip registration.
- Every other function in the API is module-level (no server argument), so `init/1` must publish the started instance for the module to find: put the server pid under `{FeatureFlags, :server}` and the ETS table name under `{FeatureFlags, :table_name}` in `:persistent_term`.
- Writes route through the published pid; reads route through the published table.
- Reads fall back to `:feature_flags` when nothing has been published yet.
- Consequence: the MOST RECENTLY STARTED instance serves the module-level API, regardless of which `:name` or `:table_name` it was started with.

**Writes**
- `FeatureFlags.enable(flag_name)` — sets the flag to `:on` for everyone. Returns `:ok`.
- `FeatureFlags.disable(flag_name)` — sets the flag to `:off` for everyone. Returns `:ok`.
- `FeatureFlags.enable_for_percentage(flag_name, percentage)` — sets the flag to `:percentage` mode with an integer value between `0` and `100`. Returns `:ok`.
- `0` is equivalent to `:off`; `100` is equivalent to `:on`.
- Guard `percentage`: a non-integer or out-of-range value raises `FunctionClauseError` and stores nothing (the flag stays unknown).
- All writes (`enable`, `disable`, `enable_for_percentage`) go through the GenServer via `call` to serialise updates.

**Reads**
- `FeatureFlags.enabled?(flag_name)` — `true` if the flag is `:on`, `false` otherwise (`:off` and `:percentage` flags return `false` here). Unknown flags default to `false`.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — `true` if the flag is `:on`, or if the flag is in `:percentage` mode and the user falls within the enabled bucket.
- Bucketing must be **deterministic**: the same `{flag_name, user_id}` pair always produces the same result across calls.
- Compute the 0–99 hash with `:erlang.phash2({flag_name, user_id}, 100)`; the user is in the bucket when that hash is **strictly less than** the percentage (a hash exactly equal to the percentage is excluded).
- If the flag is `:off`, always return `false`. Unknown flags default to `false`.

**ETS table**
- Type `:set`, `read_concurrency: true`, owned by the GenServer.
- Named, so any process can read directly without going through the GenServer process for `enabled?` and `enabled_for?` reads.
- Created in `init/1`; the table name accessible via a module attribute or passed through the GenServer state.

**Deliverable**
- The complete module in a single file.
