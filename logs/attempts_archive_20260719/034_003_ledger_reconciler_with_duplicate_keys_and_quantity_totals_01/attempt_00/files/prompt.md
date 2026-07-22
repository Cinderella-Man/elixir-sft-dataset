Write me an Elixir module called `LedgerReconciler` that reconciles two lists of
records using **bag (multiset) semantics** rather than set semantics. Unlike a
plain key diff, keys are allowed to repeat on either side, and reconciliation is
about whether the two sides *balance* — either by row count per key, or by the sum
of a numeric quantity field per key.

I need this public API:

- `LedgerReconciler.reconcile(left, right, opts)` where `left` and `right` are lists
  of maps and `opts` is a keyword list. It returns a map with two keys:
  - `:balanced` — a list of `%{key: key_map, left_total: number, right_total: number, left: [record], right: [record]}`
    entries, one per key whose left total equals its right total.
  - `:discrepancies` — a list of `%{key: key_map, left_total: number, right_total: number, delta: number, left: [record], right: [record]}`
    entries, one per key whose left total differs from its right total. `delta` is
    `left_total - right_total` (positive → surplus on the left, negative → surplus on
    the right).

`key_map` is a map of `%{key_field => value}`. `left` / `right` in each entry are the
grouped records for that key on each side, in their original input order (an empty
list when the key is absent on that side).

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms forming the composite key used to group
  records (e.g. `[:sku]` or `[:warehouse, :sku]`).
- `:quantity_field` (optional) — an atom. When given, a key's total on each side is
  the **sum** of that field across the side's records for that key. A record missing
  the field contributes `0`. When omitted or `nil`, a key's total is the **number of
  records** for that key on that side.

Behaviour requirements:
- Every key that appears on either side must appear in exactly one of `:balanced` or
  `:discrepancies`.
- Composite keys must require all key fields to be equal.
- Row counts on the two sides may differ while still balancing (e.g. two rows summing
  to 5 on the left vs one row of 5 on the right).
- A key present on only one side is a discrepancy whose absent side has total `0`.
- Order of results does not matter, but grouped records within an entry keep input
  order.
- The function must be pure — no processes, no side effects, no external
  dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.