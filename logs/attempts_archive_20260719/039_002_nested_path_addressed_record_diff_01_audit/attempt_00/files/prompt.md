Write me an Elixir module called `NestedRecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff — but unlike a shallow field-by-field diff, this one must descend into **nested maps** and report every change addressed by a dotted path.

I need these functions in the public API:
- `NestedRecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps (whose values may themselves be maps, nested to arbitrary depth). It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with three keys:
  - `:added` — a list of whole records present in `new_list` but not in `old_list`
  - `:removed` — a list of whole records present in `old_list` but not in `new_list`
  - `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`) and a `:changes` map where each key is a **dotted path string** (e.g. `"address.city"`) locating a changed leaf, and each value is a two-element tuple `{old_value, new_value}`

Path rules:
- Recurse into a field only when the value is a map in BOTH versions of the record. Two nested maps are compared key-by-key, and their dotted paths are built by joining the atom field names with `"."` (so `%{address: %{city: ...}}` yields paths like `"address.city"`).
- If a field is a map on one side and a scalar (or missing) on the other, do NOT recurse — report the whole value change at that field's path (e.g. `"address" => {%{...}, "unknown"}`).
- If a leaf field is added or removed between old and new versions of the same record, treat it as a change: use the atom `:missing` for the absent side (`{:missing, new}` for an added leaf, `{old, :missing}` for a removed one).
- Only report a `:changed` entry for a record whose comparison yields at least one path.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.