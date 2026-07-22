Implement the `assert_raises_message/3` macro. It takes an `exception` module,
a `needle` substring, and a zero-arity `fun`, and asserts two things at once:
that calling `fun` raises the given `exception`, and that the raised exception's
message (obtained via `Exception.message/1`) contains `needle` as a substring.

Because it is a macro, the generated code should run inside the caller's test so
ExUnit reports the correct file and line on failure. Use `bind_quoted` to bind
`exception`, `needle`, and `fun` into the quoted body. Invoke `fun` inside a
`try/rescue`: on success record that nothing was raised, and on `rescue` capture
the raised struct. Then distinguish and surface, via `ExUnit.Assertions.flunk/1`,
exactly three failure cases:

  1. **Nothing raised** — `fun` returned normally; report that `exception` was
     expected but no exception was raised.
  2. **Wrong exception type** — something was raised but it is not a struct of
     `exception`; report the expected type, the actual type (its `__struct__`),
     and the actual message.
  3. **Right type, non-matching message** — a struct of `exception` was raised
     but `Exception.message/1` does not contain `needle`; report the expected
     substring and the actual message.

When the right exception type is raised and its message contains `needle`, the
assertion passes (return `:ok`). Use `is_struct/2` to check the exception type
and the `=~` operator to test substring containment.

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