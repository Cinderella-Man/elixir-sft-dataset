Write me an Elixir module called `RecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff.

I need these functions in the public API:
- `RecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with three keys:
  - `:added` — a list of records present in `new_list` but not in `old_list`
  - `:removed` — a list of records present in `old_list` but not in `new_list`
  - `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`), a `:changes` map where each key is a changed field name and the value is a two-element tuple `{old_value, new_value}`

Only compare fields that exist in both versions of a record. If a field is added or removed between old and new versions of the same record, treat it as a change (old value is `:missing` if the field didn't exist before, new value is `:missing` if it was removed).

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.