Write me an Elixir module called `MultiSourceReconciler` that reconciles records coming from **more than two** sources at once, keyed by a shared composite key, and reports where each key is present and where the sources disagree.

I need this public API:

- `MultiSourceReconciler.reconcile(sources, opts)` where:
  - `sources` is a **map** from a source name (an atom, e.g. `:crm`, `:billing`, `:support`) to a list of record maps belonging to that source.
  - `opts` is a keyword list.

It must return a **list of entries**, one entry per distinct composite key found across *all* sources. Each entry is a map with these keys:

- `:key` — a map of `%{key_field => value}` reconstructed from the record's key fields (e.g. `%{id: 1}` or `%{org_id: 1, user_id: 10}`).
- `:present_in` — a list of the source names that have a record for this key.
- `:missing_from` — a list of the source names that do **not** have a record for this key.
- `:records` — a map of `%{source_name => record}` containing the full original record from every present source.
- `:conflicts` — a map of `%{field => %{source_name => value}}`. A field appears here **only if** the present sources do not all agree on that field's value (compared with `==`). When a field is in conflict, the inner map contains an entry for **every present source**, with the value that source holds for that field. If all present sources agree on a field, that field is absent from `:conflicts`. An entry whose present sources agree on everything has an empty `:conflicts` map.

The `opts` keyword list must support:

- `:key_fields` (required) — a list of atoms forming the composite key. Two records refer to the same entity if and only if all key fields are equal.
- `:compare_fields` (optional) — a list of atoms specifying which fields to check for conflicts. If omitted or `nil`, conflicts are checked on every field that appears in any present record, minus the key fields.

Behaviour requirements:
- Key matching must be exact; composite keys (`[:org_id, :user_id]`) must match only when **all** key fields are equal.
- If a compare field is missing from one of the present records, treat its value as `nil` for that source. So a source that lacks the field and a source that has it are in conflict, and the missing source's value is recorded as `nil` in the inner map.
- If the same key appears more than once within a single source's list, the last occurrence wins for that source.
- Order of the returned entries does not matter, and the order of names inside `:present_in` and `:missing_from` does not matter.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.