# Design Brief: `Reconciler` Module

## Problem

Two lists of records must be reconciled against each other by a shared key so that a structured diff can be produced. Implement an Elixir module called `Reconciler` that takes two lists of records, matches them by a shared key, and reports what is common, what differs, and what is unique to each side.

## Constraints

- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.
- Key matching must be exact. Two records match if and only if all key fields have equal values.
- Composite keys must work correctly — `[:org_id, :user_id]` should only match records where both fields are equal.
- Field comparison must be value-exact (using `==`).
- Records in `:matched` must include both the original left and right record in full, even if some fields are excluded from comparison.
- If a `compare_fields` field is missing from one or both records, treat the missing value as `nil` and diff accordingly.
- Order of results does not matter.
- Deliver the complete module in a single file.

## Required Interface

1. `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps, and `opts` is a keyword list. It should return a map with three keys:
   1. `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for records present in both lists. `diff_map` is a map of `%{field => %{left: val, right: val}}` for any fields whose values differ. It is empty if the records are identical on all compared fields.
   2. `:only_in_left` — a list of records present in `left` but absent in `right`.
   3. `:only_in_right` — a list of records present in `right` but absent in `left`.
2. The `opts` keyword list must support:
   1. `:key_fields` (required) — a list of atoms that together form the composite key used to match records across the two lists (e.g., `[:id]` or `[:org_id, :user_id]`).
   2. `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.

## Acceptance Criteria

- Records present in both lists are reported under `:matched`, each carrying the full original left record, the full original right record, and a diff map of differing fields.
- The diff map for a matched pair is empty when the records are identical on all compared fields.
- Records present only in `left` are reported under `:only_in_left`; records present only in `right` are reported under `:only_in_right`.
- Single-field keys such as `[:id]` and composite keys such as `[:org_id, :user_id]` both match correctly, with composite keys matching only when every key field is equal.
- Field diffs are computed with `==`, and a `compare_fields` field missing from one or both records is diffed as `nil`.
- Validate `:key_fields`: if it is missing from `opts`, `nil`, not a list, an empty list, or contains any element that is not an atom, raise an `ArgumentError`.
