Write me an Elixir module called `RecordMerge` that performs a **three-way merge** of record lists keyed by ID — the diff3 problem applied to lists of maps. Given a common ancestor plus two independently edited versions, it must produce the merged result and report the conflicts it could not resolve automatically.

I need these functions in the public API:
- `RecordMerge.merge(base_list, ours_list, theirs_list, opts \\ [])` where all three are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with two keys:
  - `:merged` — the list of successfully merged records, sorted ascending by key value. Conflicted and deleted records are NOT included here.
  - `:conflicts` — the list of conflict descriptors, sorted ascending by key value.

Resolution rules, per id (looking at its presence/value in base `b`, ours `o`, theirs `t`):
- **Added on one side only** (absent in base): take that side's record into `:merged`.
- **Added on both sides** (absent in base, present in ours and theirs): if `o == t`, take it; otherwise emit a conflict `%{key => id, type: :add_add, ours: o, theirs: t}`.
- **Deleted on both sides** (in base, absent in ours and theirs): drop it (no merged record, no conflict).
- **Deleted on one side, unchanged on the other** (e.g. absent in ours, and `t == b`): drop it.
- **Deleted on one side, modified on the other**: emit `%{key => id, type: :delete_modify, deleted_by: :ours | :theirs, modified: <the surviving modified record>}`.
- **Present in base, ours, and theirs**: do a **field-level** three-way merge over the union of fields (using `:missing` for a field absent on a side):
  - if `ov == tv`, keep that value;
  - else if `ov == bv`, keep theirs (`tv`);
  - else if `tv == bv`, keep ours (`ov`);
  - else this field conflicts.
  A field whose resolved value is `:missing` is omitted from the merged record (it was deleted). If any field conflicts, emit `%{key => id, type: :modify_modify, fields: %{field => %{base: bv, ours: ov, theirs: tv}}}` (only the conflicting fields) and produce NO merged record for that id; otherwise put the reconstructed record into `:merged`.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.