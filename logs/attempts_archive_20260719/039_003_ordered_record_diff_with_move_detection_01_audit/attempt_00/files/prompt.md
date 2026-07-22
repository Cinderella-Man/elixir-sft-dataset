Write me an Elixir module called `OrderedRecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff that is **order-aware**: the lists are treated as ordered sequences, so besides additions, removals, and field-level changes, the diff must also detect records that were **moved** to a different position.

I need these functions in the public API:
- `OrderedRecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with four keys:
  - `:added` — whole records present in `new_list` but not in `old_list`, in `new_list` order
  - `:removed` — whole records present in `old_list` but not in `new_list`, in `old_list` order
  - `:changed` — one entry per record present in both lists whose fields differ, in `new_list` order. Each entry is `%{key => id, changes: %{field => {old_value, new_value}}}` (fields present in only one version use `:missing` as the absent-side value, exactly as in the base task)
  - `:moved` — one entry per record whose relative order changed, in `new_list` order. Each entry is `%{key => id, from: old_index, to: new_index}` where the indices are the record's absolute 0-based positions in `old_list` and `new_list`

Move-detection rules:
- Consider only the records that exist in BOTH lists. Take their id sequence in old order and in new order and compute a Longest Common Subsequence (LCS) of the two. The ids that belong to the LCS are the "stable" anchors; every other common id is reported as moved. When the LCS is ambiguous (several are equally long), prefer, at each step, the match that keeps the later element of the new sequence (i.e. when the "skip in new" and "skip in old" branches tie in length, keep the "skip in new" branch).
- A record can appear in BOTH `:changed` and `:moved` if it was reordered and its fields also changed — the two are independent.
- Field-level changes are computed for every common record regardless of whether it moved.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.