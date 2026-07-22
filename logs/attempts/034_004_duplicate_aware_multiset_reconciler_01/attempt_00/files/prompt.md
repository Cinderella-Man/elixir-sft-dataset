Write me an Elixir module called `Reconciler` that reconciles two lists of records by a shared key — but in this variation keys are **not assumed to be unique**. The same composite key may appear multiple times on either side, and the engine must treat these as a multiset: group records by key, report which keys are shared vs. side-exclusive, and surface duplicate keys explicitly.

I need this public API:

- `Reconciler.reconcile(left, right, opts)` where `left` and `right` are lists of maps, and `opts` is a keyword list. It returns a map with **four** keys:
  - `:matched` — a list of `%{key: key_map, left: left_records, right: right_records}` entries, one per composite key that appears on **both** sides. `key_map` is a map of `%{key_field => value}` for each field in the composite key. `left_records` is the list of all left records sharing that key, and `right_records` is the list of all right records sharing that key; both are non-empty.
  - `:only_in_left` — a list of `%{key: key_map, records: records}` entries, one per composite key that appears **only** on the left side. `records` is the list of all left records with that key.
  - `:only_in_right` — a list of `%{key: key_map, records: records}` entries, one per composite key that appears **only** on the right side. `records` is the list of all right records with that key.
  - `:duplicates` — a list of `%{key: key_map, side: side, count: count}` entries, one per `(key, side)` combination where **more than one** record shares that composite key on that side. `side` is `:left` or `:right`, and `count` is how many records share the key on that side. A key can produce two `:duplicates` entries (one per side) if it is duplicated on both sides.

The `opts` keyword list must support:

- `:key_fields` (required) — a list of atoms that together form the composite key (e.g., `[:id]` or `[:org_id, :user_id]`). Key matching is exact: a key appears on a side if any record on that side has those exact key-field values.

Behaviour requirements:

- Composite keys (`[:org_id, :user_id]`) must group records only when every key field is equal.
- Within each group (`left_records`, `right_records`, and the `records` list of the only-lists), records must appear in the same relative order as they appeared in the corresponding input list.
- `key_map` must contain exactly the key fields mapped to their values — e.g. for `key_fields: [:org_id, :user_id]` and a record with `org_id: 1, user_id: 10`, the `key_map` is `%{org_id: 1, user_id: 10}`.
- The order of entries in each of the four top-level lists does not matter.
- A key that appears exactly once on each side still goes into `:matched` (with single-element `left`/`right` lists) and produces **no** `:duplicates` entry.
- The function must be pure — no processes, no side effects, no external dependencies. Use only the Elixir standard library.

Give me the complete module in a single file.