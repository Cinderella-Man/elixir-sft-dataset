Write me an Elixir module called `FeatureFlags` that manages **multivariate** feature flags (A/B/C-style experiments) using ETS for fast reads, backed by a GenServer for writes.

Unlike a plain on/off flag, a multivariate flag deterministically assigns each user to one of several named **variants** according to a weighted split, so you can run experiments where (say) 50% of users see variant `:a`, 30% see `:b`, and 20% see `:c`.

I need these functions in the public API:

- `FeatureFlags.start_link(opts)` to start the process. It should accept an optional `:table_name` for the ETS table (default `:feature_flags`), and an optional `:name` for process registration (pass `nil` to skip registration). Because every other function in the API is module-level (no server argument), `init/1` must publish the started instance for the module to find: put the server pid under `{FeatureFlags, :server}` and the ETS table under `{FeatureFlags, :table_name}` in `:persistent_term`. Writes route through the published pid and reads through the published table, so the MOST RECENTLY STARTED instance serves the module-level API — regardless of whether it was started with a `:name`, a different `:table_name`, or `name: nil`.
- `FeatureFlags.enable(flag_name)` — sets the flag globally on (`:on`).
- `FeatureFlags.disable(flag_name)` — sets the flag globally off (`:off`).
- `FeatureFlags.set_variants(flag_name, variants)` — puts the flag into multivariate mode. `variants` is a list of `{variant_name, weight}` tuples, where `variant_name` is an atom and `weight` is a non-negative integer. Raise an `ArgumentError` if the weights do not sum to exactly `100` (an empty list sums to `0` and is therefore rejected), or if any weight is negative — even when the remaining weights would otherwise total `100`. When `set_variants` raises, the flag is left unchanged: a flag that was never set stays unknown, so `variant_for/2` returns `:off` and `enabled_for?/2` returns `false` for it. A variant with weight `0` receives no users.
- `FeatureFlags.enabled?(flag_name)` — returns `true` only when the flag is globally `:on`. Variant flags and `:off`/unknown flags return `false`.
- `FeatureFlags.variant_for(flag_name, user_id)` — returns the atom the user is assigned to:
  - `:on` flags return `:on`.
  - `:off` and unknown flags return `:off`.
  - variant flags return the assigned variant atom. The assignment must be **deterministic**: the same `{flag_name, user_id}` pair always yields the same variant. Compute `bucket = :erlang.phash2({flag_name, user_id}, 100)` (a 0–99 value) and walk the variants in the order given, accumulating weights, returning the variant whose cumulative range contains the bucket (variant 1 owns `0..w1-1`, variant 2 owns `w1..w1+w2-1`, etc.). Each range is inclusive of its lower cumulative bound and exclusive of its upper one, so a variant with weight `0` (including a leading one) owns no bucket at all.
- `FeatureFlags.enabled_for?(flag_name, user_id)` — returns `true` when `variant_for/2` is anything other than `:off`.

Note that `enable`, `disable`, and `set_variants` each overwrite whatever state the flag was previously in, so a flag can move freely between `:on`, `:off`, and variant modes.

Implementation requirements:
- ETS table should be of type `:set`, with `read_concurrency: true`, owned by the GenServer, and named so any process can read directly (for `enabled?`, `variant_for`, `enabled_for?`) without going through the GenServer.
- All writes (`enable`, `disable`, `set_variants`) must go through the GenServer via `call` to serialise updates.
- The ETS table must be created in `init/1`.

Give me the complete module in a single file. Use only the OTP standard library, no external dependencies.
