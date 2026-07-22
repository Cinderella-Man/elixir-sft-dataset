Write me an Elixir module called `ThreeWayReconciler` that performs a **three-way**
reconciliation. Instead of comparing two lists, it compares a common ancestor
(`base`) against two independently-edited versions (`left` and `right`), and works
out — field by field — which changes can be merged cleanly and which genuinely
conflict.

I need this public API:

- `ThreeWayReconciler.reconcile(base, left, right, opts)` where `base`, `left` and
  `right` are lists of maps and `opts` is a keyword list. It returns a map with
  three keys:
  - `:merged` — a list of `%{base: record, left: record, right: record, merged: record}`
    entries, one per key that is present in **all three** lists and whose field
    changes merge without conflict. The `merged` record starts from the `base`
    record and applies the resolved value of every compared field.
  - `:conflicts` — a list of `%{base: record, left: record, right: record, conflicts: conflict_map}`
    entries, one per key present in all three lists that has **at least one**
    conflicting field. `conflict_map` is `%{field => %{base: bv, left: lv, right: rv}}`
    for every conflicting field only.
  - `:unpaired` — a list of `%{key: key_map, sides: %{base: record | nil, left: record | nil, right: record | nil}}`
    entries, one per key that is **not** present in all three lists. `key_map` is a
    map of `%{key_field => value}`.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms forming the composite key used to line
  up records across the three lists (e.g. `[:id]` or `[:org_id, :user_id]`).
- `:compare_fields` (optional) — a list of atoms specifying which fields to reconcile.
  If omitted or `nil`, all fields present in any of the three records except the key
  fields are reconciled.

Per-field three-way merge rule (with `bv`/`lv`/`rv` the base/left/right values, a
missing field treated as `nil`):
- if `lv == rv` → both sides agree, resolved value is `lv`, no conflict;
- else if `lv == bv` → only `right` changed, resolved value is `rv`;
- else if `rv == bv` → only `left` changed, resolved value is `lv`;
- otherwise → the two sides changed the same field to different values: a conflict.

Behaviour requirements:
- Key matching must be exact, and composite keys must require **all** key fields to
  be equal.
- Value comparison must be value-exact (using `==`).
- A record is a conflict entry if **any** compared field conflicts, otherwise it is a
  merged entry.
- `merged`, `left`, `right` and `base` records must be carried in full, even fields
  excluded from comparison (excluded fields keep the `base` value in `merged`).
- Order of results does not matter.
- The function must be pure — no processes, no side effects, no external
  dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.