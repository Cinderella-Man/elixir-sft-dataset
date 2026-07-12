Implement the `assert_within_pct/3` macro in the `AssertHelpers` module below.

`assert_within_pct(actual, expected, pct)` must assert that `actual` is within `pct`
percent of `expected` — that is, `abs(actual - expected) <= abs(expected) * pct / 100`.
It must be a macro (not a plain function) so that ExUnit reports the correct file and
line number on failure; evaluate the three arguments exactly once by using
`quote bind_quoted: [...]`.

Inside the quoted body, compute the allowed difference (`abs(expected) * (pct / 100)`)
and the actual absolute difference (`abs(actual - expected)`). Also compute the actual
percentage delta: when `expected == 0`, the delta is `+0.0` if `actual == 0` and
`:infinity` otherwise (so that with a zero `expected` only an `actual` of `0` passes);
otherwise it is `diff / abs(expected) * 100`.

If the difference is within the allowed tolerance, the macro passes and produces no
failure. Otherwise it must call `ExUnit.Assertions.flunk/1` with a multi-line message
headed by `assert_within_pct failed` that reports the actual value, the expected value,
the absolute difference, the allowed difference (labelled with the `pct` tolerance), and
the actual percentage delta. Use `inspect/1` for the values.

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
    # TODO
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