# Design brief: `AssertHelpers`

## Problem

Test suites that check numeric results need to compare values with a tolerance rather than exactly, need to confirm that a sequence of measurements moves in one direction without plateaus, and need to confirm that a failing code path raises both the right exception type *and* an exception carrying the right message text. Writing those checks by hand inside each test produces noisy, inconsistent failure output.

The deliverable is an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. The set focuses on **numeric tolerance and exception failure semantics**.

## Constraints

- All three must be macros (not plain functions), so that ExUnit can report the correct file and line number on failure.
- Use `ExUnit.Assertions.flunk/1` for surfacing failure messages.
- The module must be a single file with no external dependencies beyond `ExUnit`.
- Deliver the complete module in a single file.

## Required interface

1. **`assert_within_pct(actual, expected, pct)`** — asserts that `actual` is within `pct` percent of `expected`, i.e. `abs(actual - expected) <= abs(expected) * pct / 100`. Handle the `expected == 0` edge case gracefully (only `actual == 0` should pass then). On failure, show the actual value, the expected value, the absolute difference, the allowed difference, and the actual percentage delta; the failure message must contain the literal substring `allowed` and must include the actual value (rendered via `inspect`).

2. **`assert_monotonic(list, direction \\ :increasing)`** — asserts that `list` is a **strictly** monotonic sequence (strictly increasing or strictly decreasing depending on `direction`, which is `:increasing` or `:decreasing`). Equal adjacent values are a violation. On failure, report the index and both elements of the first violating pair; the index is rendered 0-based as the literal substring `index N` (e.g. `index 1`), where `N` is the position of the pair's first element. The failure message must also contain the direction word as a literal substring (`increasing` or `decreasing`, matching `direction`).

3. **`assert_raises_message(exception, needle, fun)`** — asserts that calling the zero-arity `fun` raises the given `exception` module AND that the raised exception's message (via `Exception.message/1`) contains the substring `needle`. On failure, distinguish three cases: no exception was raised at all, the wrong exception type was raised, or the right type was raised but its message did not contain `needle`.

## Acceptance criteria

- `assert_within_pct` passes exactly when `abs(actual - expected) <= abs(expected) * pct / 100`, and when `expected == 0` it passes only for `actual == 0`.
- A failing `assert_within_pct` produces a message containing the literal substring `allowed` and the `inspect`-rendered actual value, alongside the expected value, absolute difference, allowed difference, and actual percentage delta.
- A failing `assert_monotonic` names the first violating pair with its two elements and the literal substring `index N` for the 0-based position of the pair's first element (e.g. `index 1`), plus the literal direction word matching `direction` (`increasing` or `decreasing`). Equal adjacent values count as violations.
- For `assert_raises_message`, when the function raises nothing at all, the failure message contains the literal substring "no exception" (e.g. "but no exception was raised").
- For `assert_raises_message`, when the wrong exception type was raised, the failure message contains the actual raised exception's module name (e.g. if a `RuntimeError` is raised the message contains the literal substring `RuntimeError`).
- For `assert_raises_message`, when the right exception type is raised but its message lacks `needle`, the failure message contains the literal substring "did not contain".
- Failures are surfaced through `ExUnit.Assertions.flunk/1`, and because all three are macros, ExUnit attributes failures to the caller's file and line.
