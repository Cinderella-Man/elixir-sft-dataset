Write me an Elixir module called `Reconciler` that reconciles record sets by a shared key, but is built to reconcile **many independent partitions concurrently** and roll the per-partition diffs up into a summary.

I need these functions in the public API:

- `Reconciler.reconcile(left, right, opts)` — the pure, single-dataset reconciler. `left` and `right` are lists of maps; `opts` is a keyword list. It returns a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for records present in both lists. `diff_map` is `%{field => %{left: val, right: val}}` for fields whose values differ (empty when identical on all compared fields).
  - `:only_in_left` — records present in `left` but absent in `right`.
  - `:only_in_right` — records present in `right` but absent in `left`.

- `Reconciler.reconcile_all(partitions, opts)` — reconciles a list of partitions concurrently. Each partition is a map `%{id: term, left: [record], right: [record]}`. It returns a map with two keys:
  - `:results` — a map of `partition_id => single_result` where each `single_result` is exactly the shape returned by `reconcile/3` for that partition's `left`/`right`.
  - `:summary` — a map `%{matched: total, only_in_left: total, only_in_right: total}` summing the sizes of the corresponding buckets across all partitions.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms forming the composite key (e.g. `[:id]` or `[:org, :uid]`), applied to every partition. Key matching is exact.
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared. Applies to every partition.
- `:max_concurrency` (optional, `reconcile_all/2` only) — maximum number of partitions reconciled in parallel. Defaults to `System.schedulers_online()`.

Behaviour requirements:
- Partitions must be reconciled independently; one partition's records never match another's.
- `reconcile_all/2` must use real concurrency (e.g. `Task.async_stream`), but the output must be **deterministic** — identical inputs must produce identical results regardless of `:max_concurrency`.
- Composite keys must work correctly. Records in `:matched` must include both original records in full. Missing compared fields are treated as `nil` and diffed with `==`.
- An empty partition list yields `%{results: %{}, summary: %{matched: 0, only_in_left: 0, only_in_right: 0}}`.
- Order of results within a bucket does not matter.
- Use only the Elixir/Erlang standard library — no external dependencies. `reconcile/3` must be pure (no processes).

Give me the complete module in a single file.