Write me an Elixir module called `BagReconciler` that reconciles two lists of records whose keys may **repeat**. Unlike a set-based reconciler (where a key identifies at most one record per side), here each side is a *bag* (multiset): the same key may occur several times in `left` and/or `right`, and the reconciler must pair occurrences up one-by-one and report the leftovers.

I need these functions in the public API:

- `BagReconciler.reconcile_bags(left, right, opts)` — `left` and `right` are lists of maps, `opts` is a keyword list. Returns a map with exactly these four keys:
  - `:pairs` — a list of `%{key: key_map, index: i, left: record, right: record, differences: diff_map}` entries, one per paired-up occurrence.
  - `:unmatched_left` — a list of `%{key: key_map, record: record}` entries for left occurrences that had no right occurrence left to pair with.
  - `:unmatched_right` — a list of `%{key: key_map, record: record}` entries for right occurrences that had no left occurrence left to pair with.
  - `:duplicate_keys` — a list of `%{key: key_map, left_count: n, right_count: m}` entries, one for every key that occurs **more than once on at least one side**.

- `BagReconciler.key_counts(records, key_fields)` — `records` is a list of maps and `key_fields` a list of atoms. Returns a map of `key_map => count`, giving how many records in `records` carry each key.

Definitions:

- A **key_map** is a map `%{field => value}` built from the key fields, e.g. `%{id: 1}` or `%{org_id: 1, user_id: 10}`. A key field missing from a record contributes `nil` as its value.
- A **diff_map** is `%{field => %{left: left_value, right: right_value}}`, containing an entry only for fields whose values differ. It is `%{}` when the two records agree on all compared fields.

The `opts` keyword list of `reconcile_bags/3` must support:

- `:key_fields` (required) — a list of atoms forming the composite key. Passing no `:key_fields`, or a value that is not a non-empty list of atoms, must raise `ArgumentError`.
- `:compare_fields` (optional) — a list of atoms to diff on paired records. If omitted or `nil`, compare every field present in either record of the pair except the key fields.

Pairing rules (this is the heart of the task):

- Group each side by key, preserving the order in which the records appear in the input list.
- For a given key with `n` left occurrences and `m` right occurrences, pair the 1st left with the 1st right, the 2nd left with the 2nd right, and so on, for `min(n, m)` pairs. The `:index` of a pair is its zero-based position within that key's group (so the first pair for a key has `index: 0`).
- The remaining `n - min(n, m)` left occurrences (the later ones, in input order) go to `:unmatched_left`; the remaining `m - min(n, m)` right occurrences go to `:unmatched_right`.
- A key that appears on only one side puts all of its occurrences into that side's unmatched list.
- `:duplicate_keys` contains an entry for a key if and only if `left_count > 1` or `right_count > 1`. `left_count`/`right_count` are the total occurrence counts on each side (either may be `0`). Keys with at most one occurrence on each side are not reported.

Other behaviour requirements:

- Key matching is exact — all key fields must be equal (`==`) for two records to share a key. Composite keys must work: `[:org_id, :user_id]` only groups records that agree on both.
- Field comparison is value-exact, using `==`.
- A record in `:pairs` must carry the full original left and right maps, even if some of their fields are excluded from comparison.
- A compare field missing from one or both records is treated as `nil` and diffed accordingly.
- The order of entries within `:pairs`, `:unmatched_left`, `:unmatched_right` and `:duplicate_keys` does not matter.
- The module must be pure — no processes, no side effects, no external dependencies. Elixir standard library only.

Give me the complete module in a single file.