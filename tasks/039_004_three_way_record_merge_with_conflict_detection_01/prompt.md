**Summary:** Implement an Elixir module `RecordMerge` that performs a three-way merge (the diff3 problem applied to lists of maps) of record lists keyed by ID: given a common ancestor plus two independently edited versions, produce the merged result and report the conflicts it could not resolve automatically.

**Public API**
- `RecordMerge.merge(base_list, ours_list, theirs_list, opts \\ [])` — all three arguments are lists of maps.
- Accepts a `:key` option, an atom specifying which field is the unique identifier; defaults to `:id`.
- Returns a map with two keys:
  - `:merged` — list of successfully merged records, sorted ascending by key value. Conflicted and deleted records are NOT included here.
  - `:conflicts` — list of conflict descriptors, sorted ascending by key value.

**Resolution rules (per id, from its presence/value in base `b`, ours `o`, theirs `t`)**
- Added on one side only (absent in base): take that side's record into `:merged`.
- Added on both sides (absent in base, present in ours and theirs): if `o == t`, take it; otherwise emit a conflict `%{key => id, type: :add_add, ours: o, theirs: t}`.
- Deleted on both sides (in base, absent in ours and theirs): drop it (no merged record, no conflict).
- Deleted on one side, unchanged on the other (e.g. absent in ours, and `t == b`): drop it.
- Deleted on one side, modified on the other: emit `%{key => id, type: :delete_modify, deleted_by: :ours | :theirs, modified: <the surviving modified record>}`.

**Present in base, ours, and theirs — field-level three-way merge over the union of fields (use `:missing` for a field absent on a side)**
- if `ov == tv`, keep that value;
- else if `ov == bv`, keep theirs (`tv`);
- else if `tv == bv`, keep ours (`ov`);
- else this field conflicts.
- A field whose resolved value is `:missing` is omitted from the merged record (it was deleted).
- If any field conflicts, emit `%{key => id, type: :modify_modify, fields: %{field => %{base: bv, ours: ov, theirs: tv}}}` (only the conflicting fields) and produce NO merged record for that id; otherwise put the reconstructed record into `:merged`.

**Constraints**
- Function must be pure — no processes, no state, no side effects.
- Use only the Elixir standard library.
- Deliver the complete module in a single file.
