Write me an Elixir module called `Reconciler` that reconciles two lists of records by a shared composite key — but instead of taking both full lists at once, it must build the reconciliation **incrementally**, one record at a time, through a pure functional accumulator. This suits streaming pipelines where left-side and right-side records arrive interleaved.

I need these public functions:

- `Reconciler.new(opts)` — returns an opaque reconciler state. `opts` is a keyword list:
  - `:key_fields` (required) — a list of atoms forming the composite match key (e.g. `[:id]` or `[:org_id, :user_id]`).
  - `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.
- `Reconciler.put_left(state, record)` — returns a new state with `record` (a map) folded into the left side.
- `Reconciler.put_right(state, record)` — returns a new state with `record` folded into the right side.
- `Reconciler.result(state)` — returns the reconciliation as a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` for keys present on both sides. `diff_map` is `%{field => %{left: val, right: val}}` for fields that differ, empty when identical on all compared fields.
  - `:only_in_left` — a list of records whose key was added only via `put_left`.
  - `:only_in_right` — a list of records whose key was added only via `put_right`.

Behaviour requirements:
- Key matching must be exact: two records match iff all key fields have equal values. Composite keys must work — `[:org_id, :user_id]` matches only when both fields are equal.
- **Last write wins per side**: if `put_left` is called more than once with the same composite key, only the most recently added left record for that key is retained (same for the right side). The final `result/1` reflects the latest record on each side per key.
- The order in which `put_left` and `put_right` are interleaved must not affect the final `result/1` — only which record was added last per key per side matters.
- Field comparison is value-exact (using `==`). If a compared field is missing from one or both records, treat the missing value as `nil` and diff accordingly.
- Matched entries must carry the full original left and right records, even if some fields are excluded from comparison.
- Order of the lists inside `result/1` does not matter.
- Everything must be pure — the state is an ordinary immutable value, no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.