# Ticket: Implement `OrderedRecordDiff`

**Summary:** Provide an Elixir module `OrderedRecordDiff` that compares two versions of an ID-keyed record list and produces a structured, **order-aware** diff. Because the lists are treated as ordered sequences, the diff must report additions, removals, field-level changes, AND records **moved** to a different position. Deliver the complete module in a single file.

**Public API**
- Implement `OrderedRecordDiff.diff(old_list, new_list, opts \\ [])`.
- `old_list` and `new_list` are both lists of maps.
- Accept a `:key` option: an atom naming the field to use as the unique identifier. Defaults to `:id`.
- Return a map with exactly four keys: `:added`, `:removed`, `:changed`, `:moved`.

**`:added`**
- Whole records present in `new_list` but not in `old_list`.
- Ordered in `new_list` order.

**`:removed`**
- Whole records present in `old_list` but not in `new_list`.
- Ordered in `old_list` order.

**`:changed`**
- One entry per record present in both lists whose fields differ, in `new_list` order.
- Each entry is `%{key => id, changes: %{field => {old_value, new_value}}}`.
- Fields present in only one version use `:missing` as the absent-side value, exactly as in the base task.
- Only fields whose values differ between the two versions appear in `changes`.
- A record whose fields are all equal is omitted from `:changed` entirely.

**`:moved`**
- One entry per record whose relative order changed, in `new_list` order.
- Each entry is `%{key => id, from: old_index, to: new_index}`, where the indices are the record's absolute 0-based positions in `old_list` and `new_list`.

**Move-detection rules**
- Consider only records that exist in BOTH lists.
- Take their id sequence in old order and in new order and compute a Longest Common Subsequence (LCS) of the two.
- Ids belonging to the LCS are the "stable" anchors; every other common id is reported as moved.
- On ambiguous LCS (several equally long): at each step, prefer the match that keeps the later element of the new sequence — i.e. when the "skip in new" and "skip in old" branches tie in length, keep the "skip in new" branch.

**Independence / interaction rules**
- A record can appear in BOTH `:changed` and `:moved` if it was reordered and its fields also changed — the two are independent.
- Field-level changes are computed for every common record regardless of whether it moved.

**Constraints**
- The function must be pure — no processes, no state, no side effects.
- Use only the Elixir standard library.
- Provide the complete module in a single file.
