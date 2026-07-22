Write me an Elixir module called `Reconciler` that takes two lists of records and reconciles them by a shared key, producing a structured diff — but with **configurable per-field comparison semantics** instead of strict value equality.

I need this function in the public API:

- `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps and `opts` is a keyword list. It returns a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for records present in both lists. `diff_map` is a map of `%{field => %{left: val, right: val}}` for any fields whose values are considered **unequal under that field's comparator**. It is empty if the records are considered equal on all compared fields.
  - `:only_in_left` — a list of records present in `left` but absent in `right`.
  - `:only_in_right` — a list of records present in `right` but absent in `left`.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms that together form the composite key used to match records across the two lists (e.g. `[:id]` or `[:org, :uid]`). Key matching is always **exact**.
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.
- `:comparators` (optional) — a map of `%{field => rule}` giving per-field comparison rules. Any field not present in the map uses exact `==`. The supported rules are:
  - `:exact` — value equality via `==` (the default).
  - `:case_insensitive` — for two binaries, equal if they match after `String.downcase/1`; otherwise falls back to `==`.
  - `{:tolerance, tol}` — for two numbers, equal if `abs(left - right) <= tol`; otherwise falls back to `==` (so `nil` vs a number is unequal).
  - a 2-arity function `fun(left_val, right_val)` returning a boolean — `true` means the two values are considered equal.

Behaviour requirements:
- Composite keys must work correctly — `[:org, :uid]` should only match records where both fields are equal.
- Records in `:matched` must include both the original left and right record in full, even if some fields are excluded from comparison.
- If a compared field is missing from one or both records, treat the missing value as `nil` and apply the field's comparator to `nil`.
- A comparator only affects the field it is assigned to; all other fields keep their own (or the default) rule.
- Order of results does not matter.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.