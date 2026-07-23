# Design Brief: `TolerantReconciler`

## Problem

Two lists of records must be reconciled against each other, but strict equality is too blunt: a 0.005 rounding difference on a money column, or a stray capital letter in a name, should not count as a mismatch. The needed component is an Elixir module called `TolerantReconciler` that reconciles two lists of records using **per-field comparison rules** instead of strict equality. The design is split into a validated-configuration stage and an execution stage.

## Constraints

- Pure functions — no processes, no side effects, no external dependencies. Elixir standard library only.
- Deliver the complete module in a single file.

## Required Interface

1. **`TolerantReconciler.compile(opts)`** — validates a keyword list and returns `{:ok, config}` or `{:error, reason}`.

   Options:
   - `:key_fields` (required) — a non-empty list of atoms forming the composite key.
   - `:compare_fields` (optional) — a list of atoms to compare on matched pairs. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.
   - `:rules` (optional) — a keyword list of `field => rule`. Any compared field with no entry here uses the `:exact` rule. Defaults to `[]`.

   Rules:
   - `:exact` — the values differ unless `left == right`.
   - `{:numeric, tolerance}` — `tolerance` must be a number `>= 0`. If **both** values are numbers, they are considered equal when `abs(left - right) <= tolerance`. If either value is not a number, fall back to `==`.
   - `:case_insensitive` — if **both** values are binaries, they are considered equal when their trimmed, downcased forms are equal (`String.trim/1` then `String.downcase/1`). If either value is not a binary, fall back to `==`.
   - `:ignore` — the field is never compared and can never appear in a differences map, even if it is listed in `:compare_fields`.

   Errors — return exactly these error tuples (first failure wins is not required — any one of the applicable errors is acceptable when several apply):
   - `{:error, :missing_key_fields}` — `:key_fields` is absent.
   - `{:error, :invalid_key_fields}` — `:key_fields` is present but is not a non-empty list of atoms.
   - `{:error, :invalid_compare_fields}` — `:compare_fields` is present, not `nil`, and is not a list of atoms.
   - `{:error, :invalid_rules}` — `:rules` is not a keyword list (a list of `{atom, term}` pairs).
   - `{:error, {:invalid_rule, field}}` — the rule given for `field` is not one of the four rules above (including a `{:numeric, tolerance}` whose tolerance is not a number `>= 0`).

   On success the return is `{:ok, config}`. The shape of `config` is up to you — treat it as opaque; it is only ever passed back into `run/3`.

2. **`TolerantReconciler.run(config, left, right)`** — runs the reconciliation, where `left` and `right` are lists of maps. Returns a report map.

   Matching: records are matched across the two lists by **exact** equality on all key fields (comparison rules apply to compared fields only, never to key fields). A key field missing from a record is treated as `nil`. If a key repeats within one list, the last record with that key wins.

   The report is a map with three keys:
   - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` for keys present on both sides. `diff_map` is `%{field => %{left: left_value, right: right_value, rule: rule}}` for every compared field whose values differ **under its rule**, where `rule` is the rule that was applied (`:exact` when the field had no entry in `:rules`). `diff_map` is `%{}` when the pair agrees under all rules. A compared field missing from a record is treated as `nil`. The `:left` and `:right` records are the full originals.
   - `:only_in_left` — records whose key appears only in `left`.
   - `:only_in_right` — records whose key appears only in `right`.

   Order of results does not matter.

3. **`TolerantReconciler.field_summary(report)`** — takes a report from `run/3` and returns a map of `%{field => number_of_matched_pairs_where_it_differed}`. Given a report from `run/3`, return a map from field name to the number of entries in `:matched` whose `differences` map contains that field. Fields that never differed are **omitted** from the map (so an all-clean report gives `%{}`).

## Acceptance Criteria

- `compile/1` validates the keyword list, returns `{:ok, config}` on success and the exact error tuples above on failure, applies the rule semantics described (`:exact`, `{:numeric, tolerance}` with `tolerance` a number `>= 0`, `:case_insensitive`, `:ignore`), and defaults `:rules` to `[]` with `:exact` for any compared field lacking an entry.
- `run/3` matches by exact equality on all key fields (missing key field treated as `nil`, last record wins on repeated keys within a list), produces `:matched`, `:only_in_left`, and `:only_in_right`, and builds each `diff_map` correctly (missing compared field treated as `nil`, `:ignore` fields never present, `%{}` when a pair agrees).
- `field_summary/1` returns a map from field to the count of `:matched` entries whose `differences` contains that field, omitting fields that never differed (`%{}` for an all-clean report).
- The module is pure — no processes, no side effects, no external dependencies, Elixir standard library only — and delivered complete in a single file.
