# Design Brief: `RecordDiff`

## Problem & Constraints

We need to compare two versions of a record list — each keyed by an ID — and produce a structured diff. Build an Elixir module called `RecordDiff` that does this.

Constraints on the implementation:

- Both inputs are lists of maps.
- A record counts as modified only if at least one field actually differs; records that are identical in both lists must not appear in `:changed`.
- Fields must be compared across both versions of a record. If a field is added or removed between old and new versions of the same record, treat it as a change: the old value is `:missing` if the field didn't exist before, and the new value is `:missing` if it was removed.
- The function must be pure — no processes, no state, no side effects.
- Use only the Elixir standard library.
- Deliver the complete module in a single file.

## Required Interface

The public API must provide the following:

1. `RecordDiff.diff(old_list, new_list, opts \\ [])`, where both lists are lists of maps.
2. It must accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`).
3. It must return a map with three keys:
   1. `:added` — a list of records present in `new_list` but not in `old_list`.
   2. `:removed` — a list of records present in `old_list` but not in `new_list`.
   3. `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`), and a `:changes` map where each key is a changed field name and the value is a two-element tuple `{old_value, new_value}`.

## Acceptance Criteria

- Identical records are excluded from `:changed`; a record appears there only when at least one field differs.
- Added or removed fields on the same record are reported as changes, using `:missing` for the absent side (old value `:missing` when newly added, new value `:missing` when removed).
- When both lists are empty, the diff is `%{added: [], removed: [], changed: []}`.
- The function is pure: no processes, no state, no side effects, standard library only.
