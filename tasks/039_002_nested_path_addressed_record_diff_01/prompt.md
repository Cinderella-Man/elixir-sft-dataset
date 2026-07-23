Hey — could you write me an Elixir module called `NestedRecordDiff`? I need it to compare two versions of a record list keyed by ID and produce a structured diff, but here's the twist: unlike a shallow field-by-field diff, this one has to descend into nested maps and report every change addressed by a dotted path.

For the public API, I'm after these functions:

I want `NestedRecordDiff.diff(old_list, new_list, opts \\ [])`, where both lists are lists of maps (and those maps' values may themselves be maps, nested to arbitrary depth). It should accept a `:key` option — an atom specifying which field to use as the unique identifier — defaulting to `:id`. It should return a map with three keys:
- `:added` — a list of whole records present in `new_list` but not in `old_list`
- `:removed` — a list of whole records present in `old_list` but not in `new_list`
- `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`) and a `:changes` map where each key is a dotted path string (e.g. `"address.city"`) locating a changed leaf, and each value is a two-element tuple `{old_value, new_value}`

A few rules I care about for the paths:
- Recurse into a field only when the value is a map in BOTH versions of the record. Two nested maps get compared key-by-key, and their dotted paths are built by joining the atom field names with `"."` (so `%{address: %{city: ...}}` yields paths like `"address.city"`).
- If a field is a map on one side and a scalar (or missing) on the other, do NOT recurse — just report the whole value change at that field's path (e.g. `"address" => {%{...}, "unknown"}`).
- If a leaf field is added or removed between the old and new versions of the same record, treat it as a change: use the atom `:missing` for the absent side (`{:missing, new}` for an added leaf, `{old, :missing}` for a removed one).
- Only report a `:changed` entry for a record whose comparison yields at least one path.

One more thing — the function has to be pure: no processes, no state, no side effects. Please stick to the Elixir standard library only.

Send me the complete module in a single file.
