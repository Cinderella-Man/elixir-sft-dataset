# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

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

## The buggy module

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for numeric tolerance and exception semantics.

  ## Usage

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use AssertHelpers

        test "example" do
          assert_within_pct(measured, 100, 5)
          assert_monotonic(timestamps)
          assert_raises_message(ArgumentError, "invalid", fn -> parse!("x") end)
        end
      end
  """

  @doc false
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_within_pct/3
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `actual` is within `pct` percent of `expected`:

      abs(actual - expected) <= abs(expected) * pct / 100

  When `expected == 0`, only `actual == 0` passes. On failure the message
  shows the values, the absolute difference, the allowed difference, and the
  actual percentage delta.
  """
  @spec assert_within_pct(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_within_pct(actual, expected, pct) do
    quote bind_quoted: [actual: actual, expected: expected, pct: pct] do
      allowed = abs(expected) * (pct / 100)
      diff = abs(actual - expected)

      actual_pct =
        if expected == 0 do
          if actual == 0, do: +0.0, else: :infinity
        else
          diff / abs(expected) * 100
        end

      unless diff <= allowed do
        ExUnit.Assertions.flunk("""
        assert_within_pct failed

          actual          : #{inspect(actual)}
          expected        : #{inspect(expected)}
          difference      : #{inspect(diff)}
          allowed (±#{pct}%) : #{inspect(allowed)}
          actual delta    : #{inspect(actual_pct)}%
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_monotonic/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `list` is a strictly monotonic sequence in `direction`
  (`:increasing` or `:decreasing`). Equal adjacent values are a violation.

  On failure reports the index and both elements of the first violating pair.
  """
  @spec assert_monotonic(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_monotonic(list, direction \\ :increasing) do
    quote bind_quoted: [list: list, direction: direction] do
      items = Enum.to_list(list)

      case AssertHelpers.__first_non_monotonic__(items, direction) do
        :ok ->
          :ok

        {:violation, index, a, b} ->
          ExUnit.Assertions.flunk("""
          assert_monotonic (#{direction}) failed

            sequence is not strictly #{direction}
            violation at index #{index}:
              element #{index}     : #{inspect(a)}
              element #{index + 1} : #{inspect(b)}
            full sequence: #{inspect(items)}
          """)
      end
    end
  end

  # Public so the macro-generated `quote` block can call it from any module.
  @doc false
  @spec __first_non_monotonic__([term()], :increasing | :decreasing) ::
          :ok | {:violation, non_neg_integer(), term(), term()}
  def __first_non_monotonic__(items, direction) do
    items
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {[a, b], i} ->
      ok? =
        case direction do
          :increasing -> a < b
          :decreasing -> a > b
        end

      if ok?, do: true, else: {:violation, i, a, b}
    end)
  end

  # ---------------------------------------------------------------------------
  # assert_raises_message/3
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that the zero-arity `fun` raises `exception` and that the raised
  exception's message contains the substring `needle`.

  On failure distinguishes three cases: nothing raised, wrong exception type,
  or right type but non-matching message.
  """
  @spec assert_raises_message(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_raises_message(exception, needle, fun) do
    quote bind_quoted: [exception: exception, needle: needle, fun: fun] do
      result =
        try do
          fun.()
          {:no_raise, nil}
        rescue
          e -> {:raised, e}
        end

      case result do
        {:no_raise, _} ->
          ExUnit.Assertions.flunk("""
          assert_raises_message failed

            expected #{inspect(exception)} to be raised
            but no exception was raised
          """)

        {:raised, e} ->
          cond do
            not is_struct(e, exception) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                expected exception: #{inspect(exception)}
                actual exception  : #{inspect(e.__struct__)}
                message           : #{inspect(Exception.message(e))}
              """)

            not (Exception.message(e) =~ needle) ->
              ExUnit.Assertions.flunk("""
              assert_raises_message failed

                exception #{inspect(exception)} was raised as expected
                but its message did not contain the expected text
                expected substring: #{inspect(needle)}
                actual message    : #{inspect(Exception.message(e))}
              """)

            true ->
              :ok
          end
      end
    end
  end
end
```

## Failing test report

```
4 of 15 test(s) failed:

  * test assert_monotonic/2 passes for a strictly increasing sequence
      no case clause matching:
      
          true
      

  * test assert_monotonic/2 passes for a strictly decreasing sequence
      no case clause matching:
      
          true
      

  * test assert_monotonic/2 fails for equal adjacent values (not strict)
      no case clause matching:
      
          true
      

  * test assert_monotonic/2 fails when an increasing sequence dips
      no case clause matching:
      
          true
```
