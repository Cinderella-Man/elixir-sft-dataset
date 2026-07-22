Write me an Elixir module called `TolerantReconciler` that reconciles records with **per-field comparison rules** rather than strict equality, and classifies every matched pair by how badly it disagrees.

Real-world reconciliation between two systems rarely finds byte-identical records: a float may be off by rounding, a name may differ only in case or padding. Those benign differences must be reported but must *not* be treated as conflicts.

I need these functions in the public API:

- `TolerantReconciler.diff_pair(left, right, opts)` — compares two maps and returns `{status, diff_map}`.
- `TolerantReconciler.reconcile_all(left, right, opts)` — reconciles two lists of maps by a composite key and buckets the results.
- `TolerantReconciler.summary(result)` — takes the map returned by `reconcile_all/3` and returns counts.

## Rules

A **rule** describes how one field is compared. Supported rules:

- `:exact` — the values must be equal (`==`). Any difference is a conflict.
- `{:numeric, tolerance}` — the difference is *tolerable* if both values are numbers (integer or float) and `abs(left - right) <= tolerance`. Otherwise it is a conflict.
- `:case_insensitive` — the difference is *tolerable* if both values are binaries and they are equal after trimming leading/trailing whitespace and downcasing. Otherwise it is a conflict.

Rules are supplied via the `:rules` option as a map or keyword list of `field => rule`. Any field with no rule defaults to `:exact`.

## `diff_pair/3`

`opts` supports:

- `:rules` (optional, default none) — the `field => rule` mapping described above.
- `:ignore_fields` (optional, default `[]`) — a list of atoms to exclude from comparison entirely.

The compared fields are every field present in `left` or in `right`, minus `:ignore_fields`. A field missing from one map is read as `nil`.

For each compared field:

- if the two values are equal (`==`), the field does not appear in the diff map;
- otherwise the field appears as `field => %{left: left_value, right: right_value, status: field_status}` where `field_status` is `:within_tolerance` if the field's rule tolerates the difference (per the rules above) and `:conflict` if it does not.

The returned `status` is:

- `:identical` if the diff map is empty;
- `:conflict` if any field in the diff map has `status: :conflict`;
- `:within_tolerance` otherwise (there are differences, but every one of them is tolerated).

## `reconcile_all/3`

`opts` supports:

- `:key_fields` (required) — a non-empty list of atoms forming the composite key. Missing or invalid must raise `ArgumentError`.
- `:rules` (optional) — as above.
- `:ignore_fields` (optional, default `[]`) — extra fields to exclude. The key fields are **always** excluded from comparison, whether or not they are listed.

It returns a map with exactly these five keys:

- `:identical`, `:within_tolerance`, `:conflicts` — lists of `%{key: key_map, left: record, right: record, differences: diff_map}` entries for keys present on both sides, bucketed by the pair's `diff_pair/3` status (`:conflict` pairs go into `:conflicts`).
- `:only_in_left` — the raw left records whose key is absent from `right`.
- `:only_in_right` — the raw right records whose key is absent from `left`.

Where a `key_map` is `%{field => value}` over the key fields (a missing key field contributes `nil`). If the same key occurs more than once on a side, the last record with that key in the input list wins. Order within each bucket does not matter.

## `summary/1`

Given a `reconcile_all/3` result, returns

```
%{
  identical: n,
  within_tolerance: n,
  conflicts: n,
  only_in_left: n,
  only_in_right: n,
  matched: n            # identical + within_tolerance + conflicts
}
```

Other requirements: the module must be pure — no processes, no side effects — and use only the Elixir standard library.

Give me the complete module in a single file.