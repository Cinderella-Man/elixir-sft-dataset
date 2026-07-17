Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. This set focuses on **numeric tolerance and exception failure semantics**.

I need these macros:

- `assert_within_pct(actual, expected, pct)` — asserts that `actual` is within `pct` percent of `expected`, i.e. `abs(actual - expected) <= abs(expected) * pct / 100`. Handle the `expected == 0` edge case gracefully (only `actual == 0` should pass then). On failure, show the actual value, the expected value, the absolute difference, the allowed difference, and the actual percentage delta.

- `assert_monotonic(list, direction \\ :increasing)` — asserts that `list` is a **strictly** monotonic sequence (strictly increasing or strictly decreasing depending on `direction`, which is `:increasing` or `:decreasing`). Equal adjacent values are a violation. On failure, report the index and both elements of the first violating pair; the index is rendered 0-based as the literal substring `index N` (e.g. `index 1`), where `N` is the position of the pair's first element.

- `assert_raises_message(exception, needle, fun)` — asserts that calling the zero-arity `fun` raises the given `exception` module AND that the raised exception's message (via `Exception.message/1`) contains the substring `needle`. On failure, distinguish three cases: no exception was raised at all, the wrong exception type was raised, or the right type was raised but its message did not contain `needle`.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit`.

Give me the complete module in a single file.

## Additional interface contract

- In the `assert_raises_message` case where the function raises nothing at all, the failure message must contain the literal substring "no exception" (e.g. "but no exception was raised").