# Data Quality Scorer

Write me an Elixir module called `DataQualityScorer` that scores the quality of a
dataset (a list of records) against a set of declarative quality rules.

## Public API

Expose a single function:

```elixir
DataQualityScorer.score(records, rules)
```

- `records` is a list of maps. Each map is one record. Keys are field names
  (atoms), values are arbitrary. Records may be missing some keys.
- `rules` is a map of the form `%{field_name => [rule, ...]}`. Each field maps to
  a **non-empty list** of rules to enforce on that field. Fields that appear in a
  record but not in `rules` are ignored.

## Rule types

Each rule is evaluated against a single record's value for its field. Use
`Map.get(record, field)` to fetch the value (so a missing key yields `nil`).

- `:not_null` — passes when the field key is present **and** its value is not
  `nil`. (A missing key fails. A present key with value `nil` fails.)
- `:unique` — passes when this record's value for the field appears **exactly
  once** across all records in the dataset. Tally the value returned by
  `Map.get(record, field)` for every record (a missing key contributes `nil`); a
  record passes when the frequency of its own value is `1`. If two or more records
  share the same value (including `nil`), all of them fail this rule.
- `{:format, regex}` — passes when the value is a **binary string** and
  `Regex.match?(regex, value)` is true. A `nil` or non-string value fails.
- `{:range, min, max}` — passes when the value is a **number** (integer or float)
  and `min <= value <= max` (bounds are inclusive). A `nil` or non-number value
  fails.
- `{:referential, set}` — passes when the value is a member of the provided
  `MapSet`, i.e. `MapSet.member?(set, value)` is true.

## Return value

Return a map with exactly these keys:

```elixir
%{
  overall: float,
  records: [%{score: float, passed: non_neg_integer, total: non_neg_integer}, ...],
  fields:  %{field_name => float}
}
```

### `records`
A list, in the **same order as the input `records`**, of per-record results.
For a record:

- `total` is the total number of individual rule instances across all fields
  (this is the same for every record: the sum of the lengths of every field's
  rule list).
- `passed` is how many of those rule instances evaluate to true for that record.
- `score` is `passed / total * 100` as a float. If `total` is `0` (no rules at
  all), `score` is `100.0`.

### `fields`
A map from each field name (every key present in `rules`) to a percentage float.
A record **passes a field** when **all** of that field's rules pass for it. The
field's score is `(number of records that pass the field) / (number of records) *
100`. If the dataset is empty, every field scores `100.0` (vacuously true).

### `overall`
The percentage of all `(record, rule)` checks that pass:
`(sum of every record's passed) / (number_of_records * total_rules) * 100` as a
float. If the dataset is empty, or there are no rules at all, `overall` is
`100.0`.

## Notes

- Percentages are plain floats (e.g. `75.0`, `66.666...`). Do not round.
- Use only the Elixir/Erlang standard library — no external dependencies.
- Give me the complete module in a single file.