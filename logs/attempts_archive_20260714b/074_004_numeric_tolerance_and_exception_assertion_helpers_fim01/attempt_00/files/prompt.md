# Task

The module below, `AssertHelpers`, provides three custom ExUnit assertion macros. Two of them (`assert_within_pct/3` and `assert_monotonic/2`) are already implemented. Your job is to implement the body of the third one: **`assert_raises_message/3`**.

## What `assert_raises_message/3` must do

`assert_raises_message(exception, needle, fun)` is a macro (not a plain function, so that ExUnit reports the correct file and line on failure). It takes:

- `exception` — an exception module (e.g. `ArgumentError`, `RuntimeError`, or a custom `defexception` module),
- `needle` — a substring that the raised exception's message must contain,
- `fun` — a zero-arity function.

The macro must expand to code that:

1. Invokes `fun.()` inside a `try/rescue`, capturing whether an exception was raised and, if so, which one. Bind the macro arguments with `quote bind_quoted: [...]` so each is evaluated exactly once.
2. Passes (returns `:ok`) only when **both** conditions hold: the raised exception is a struct of the given `exception` module, **and** `Exception.message/1` on it contains `needle` as a substring (use `=~`).
3. Fails via `ExUnit.Assertions.flunk/1` otherwise, distinguishing three distinct failure cases with different messages:
   - **Nothing was raised** — `fun.()` returned normally. The failure message must state the expected exception module and must contain the literal substring `"no exception"` (e.g. `"but no exception was raised"`).
   - **Wrong exception type** — an exception was raised but it is not a struct of `exception`. The message should show the expected exception module, the actual exception module (its `__struct__`), and the actual message.
   - **Right type, wrong message** — the correct exception module was raised, but its message does not contain `needle`. The message should say the exception was raised as expected, then show the expected substring and the actual message.

Keep the failure output in the same style as the other macros in the module: a heading line `assert_raises_message failed`, a blank line, then indented labelled fields, using `inspect/1` for values.

## Module

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

      if ok?, do: false, else: {:violation, i, a, b}
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
    # TODO
  end
end
```