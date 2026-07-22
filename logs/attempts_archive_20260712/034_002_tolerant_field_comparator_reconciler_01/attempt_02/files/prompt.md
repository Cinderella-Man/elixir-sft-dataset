Write me an Elixir module called `Reconciler` that takes two lists of records and reconciles them by a shared key, producing a structured diff. Unlike a plain exact-match diff, this variation must support **pluggable per-field comparators** so that fields can be compared with tolerance, case-insensitivity, or custom logic rather than always with `==`.

I need this public API:

- `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps, and `opts` is a keyword list. It returns a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for records whose key is present in both lists. `diff_map` is a map of `%{field => %{left: val, right: val}}` for any compared field whose two values are considered **different** by that field's comparator. It is empty (`%{}`) if the records are considered equal on all compared fields.
  - `:only_in_left` — a list of records present in `left` but absent in `right`.
  - `:only_in_right` — a list of records present in `right` but absent in `left`.

The `opts` keyword list must support:

- `:key_fields` (required) — a list of atoms that together form the composite key used to match records across the two lists (e.g., `[:id]` or `[:org_id, :user_id]`). Key matching is always **exact**: two records match if and only if all key fields have equal values. Comparators never affect key matching.
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields (across both records) are compared.
- `:comparators` (optional) — a map of `%{field => comparator}`. If omitted, it defaults to the empty map. Any compared field **not** present in this map is compared with `==`. A `comparator` is one of:
  - `{:numeric, tolerance}` — if both values are numbers, they are considered equal when `abs(left - right) <= tolerance`; otherwise they are compared with `==`.
  - `:case_insensitive` — if both values are strings (binaries), they are considered equal when `String.downcase(left) == String.downcase(right)`; otherwise they are compared with `==`.
  - a 2-arity function `fun` — the two values are considered equal when `fun.(left_val, right_val)` returns a truthy value.

Behaviour requirements:

- Composite keys must work correctly — `[:org_id, :user_id]` should only match records where both fields are equal.
- Records in `:matched` must include both the original left and right record in full, even if some fields are excluded from comparison.
- If a compared field is missing from one or both records, treat the missing value as `nil` and hand that `nil` to the comparator (the built-in `{:numeric, _}` and `:case_insensitive` comparators fall back to `==` when a value is not of the expected type, so a `nil` produces a difference against a present value).
- When a field differs, the reported `%{left: val, right: val}` must carry the **original** values (including `nil` for a missing field), not any transformed form.
- Order of results does not matter.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.