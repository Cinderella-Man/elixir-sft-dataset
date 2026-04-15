Write me an Elixir module called `Reconciler` that takes two lists of records and reconciles them by a shared key, producing a structured diff.

I need these functions in the public API:

- `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps, and `opts` is a keyword list. It should return a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for records present in both lists. `diff_map` is a map of `%{field => %{left: val, right: val}}` for any fields whose values differ. It is empty if the records are identical on all compared fields.
  - `:only_in_left` — a list of records present in `left` but absent in `right`.
  - `:only_in_right` — a list of records present in `right` but absent in `left`.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms that together form the composite key used to match records across the two lists (e.g., `[:id]` or `[:org_id, :user_id]`).
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.

Behaviour requirements:
- Key matching must be exact. Two records match if and only if all key fields have equal values.
- Composite keys must work correctly — `[:org_id, :user_id]` should only match records where both fields are equal.
- Field comparison must be value-exact (using `==`).
- Records in `:matched` must include both the original left and right record in full, even if some fields are excluded from comparison.
- If a `compare_fields` field is missing from one or both records, treat the missing value as `nil` and diff accordingly.
- Order of results does not matter.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.