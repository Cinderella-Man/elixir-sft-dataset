Write me an Elixir module called `Reconciler` that takes two lists of records and reconciles them by a shared key, producing a structured diff — but that treats **duplicate keys** as a first-class, explicitly reported condition instead of silently collapsing them.

I need this function in the public API:

- `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps and `opts` is a keyword list. It returns a map with four keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for keys that appear **exactly once on each side**. `diff_map` is a map of `%{field => %{left: val, right: val}}` for fields whose values differ (empty when identical on all compared fields).
  - `:only_in_left` — records for keys that appear **exactly once in `left` and not at all in `right`**.
  - `:only_in_right` — records for keys that appear **exactly once in `right` and not at all in `left`**.
  - `:duplicate_keys` — a list of `%{key: key_map, left_count: n, right_count: m}` entries for every key that appears **more than once on either side**. `key_map` is a map of `%{key_field => value}` reconstructed from the composite key. Such keys are considered ambiguous and must NOT appear in `:matched`, `:only_in_left`, or `:only_in_right`.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms forming the composite key (e.g. `[:id]` or `[:org, :uid]`). Key matching is exact.
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.

Behaviour requirements:
- A key with two or more records on the left (or on the right) is a duplicate, regardless of how many records the other side has — including zero. Report it once, with the true counts on each side.
- Composite keys must work correctly, and `:duplicate_keys` entries must express the key as a `%{field => value}` map for all key fields.
- Field comparison must be value-exact (using `==`). If a compared field is missing from one or both records, treat the missing value as `nil`.
- Records in `:matched` must include both the original left and right record in full, even if some fields are excluded from comparison.
- Order of results does not matter.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.