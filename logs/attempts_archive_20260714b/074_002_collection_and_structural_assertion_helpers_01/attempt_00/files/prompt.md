Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. This set focuses on **collections and structural data** rather than time or processes.

I need these macros:

- `assert_subset(subset, superset)` — asserts that every element of the enumerable `subset` also appears in the enumerable `superset` (set membership, so duplicates in `subset` are fine). On failure, the message should list exactly which elements are missing, plus show both collections so the developer can see what happened.

- `assert_has_keys(map, keys)` — asserts that `map` contains every key in `keys`. Accept either a list of keys or a single bare key. On failure, the message should list the missing keys, the keys that were expected, and the keys actually present on the map.

- `assert_sorted_by(enumerable, key_fun)` — asserts that `enumerable` is sorted in ascending order (non-strict, so equal adjacent keys are allowed) according to the 1-arity `key_fun` applied to each element. On failure, report the index of the first out-of-order pair together with both offending elements and their computed keys.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit`.

Give me the complete module in a single file.