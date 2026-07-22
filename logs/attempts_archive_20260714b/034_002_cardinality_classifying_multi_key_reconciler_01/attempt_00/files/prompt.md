Write me an Elixir module called `MultiKeyReconciler` that reconciles two lists of records whose keys may repeat, classifying every shared key by its match *cardinality* instead of assuming a one-to-one join.

## Public API

- `MultiKeyReconciler.classify(left, right, opts)` — `left` and `right` are lists of maps, `opts` is a keyword list. Returns a report map (described below).
- `MultiKeyReconciler.counts(report)` — takes a report produced by `classify/3` and returns a map of entry counts (described below).

## Options

- `:key_fields` (required) — a non-empty list of atoms forming the composite key (e.g. `[:id]` or `[:org_id, :user_id]`). If it is missing, or is not a non-empty list of atoms, raise `ArgumentError`.
- `:compare_fields` (optional) — a list of atoms to diff on a one-to-one pair. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.

## Grouping

Group each side by its composite key. A record's composite key is the tuple of its values at the key fields, in the order given; a key field missing from a record contributes `nil`. Records that share a composite key form one group, and **the records inside a group keep their original input order**.

Every key present on **both** sides is classified by the sizes of its two groups. Every entry carries a `:key` field, which is a **map** of `%{key_field => value}` for that group.

## The report

`classify/3` returns a map with exactly these six keys:

- `:one_to_one` — one left record and one right record for the key. Entries are
  `%{key: key_map, left: record, right: record, differences: diff_map}`.
  `diff_map` is `%{field => %{left: left_value, right: right_value}}` for each compared field whose values differ under `==`; it is `%{}` when the pair agrees on all compared fields. A compared field missing from a record is treated as `nil`. The `:left` and `:right` records are the full originals, even if some of their fields were excluded from comparison.
- `:one_to_many` — one left record, two or more right records. Entries are
  `%{key: key_map, left: record, right: [records]}`.
- `:many_to_one` — two or more left records, exactly one right record. Entries are
  `%{key: key_map, left: [records], right: record}`.
- `:many_to_many` — two or more records on both sides. Entries are
  `%{key: key_map, left: [records], right: [records]}`.
- `:only_in_left` — keys present only in `left`. Entries are `%{key: key_map, records: [records]}` (the group, which may hold one or many records).
- `:only_in_right` — keys present only in `right`. Entries are `%{key: key_map, records: [records]}`.

No `differences` map is computed for ambiguous (`one_to_many`, `many_to_one`, `many_to_many`) groups — those pairings are considered unresolvable without a tie-break rule, so the raw groups are handed back as-is.

The order of entries within each of the six lists is unspecified; only the order of records inside a group is guaranteed.

## counts/1

`MultiKeyReconciler.counts(report)` returns a map with these keys, where each value is the **number of entries** (i.e. the number of keys) in the corresponding report list:

`:one_to_one`, `:one_to_many`, `:many_to_one`, `:many_to_many`, `:only_in_left`, `:only_in_right`, plus

- `:ambiguous` — the sum of `:one_to_many`, `:many_to_one`, and `:many_to_many`.

## Constraints

- Pure functions — no processes, no side effects, no external dependencies. Elixir standard library only.
- Key matching is exact: values must be `==` on every key field.

Give me the complete module in a single file.