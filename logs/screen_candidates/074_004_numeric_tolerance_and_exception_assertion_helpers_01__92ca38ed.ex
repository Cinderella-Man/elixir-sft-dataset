defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for numeric tolerance and exception failure semantics.

  Intended to be `use`d inside a test module:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "tolerance" do
          assert_within_pct(99.5, 100.0, 1)
          assert_monotonic([1, 2, 3])
          assert_monotonic([3, 2, 1], :decreasing)
          assert_raises_message(ArgumentError, "boom", fn -> raise ArgumentError, "boom" end)
        end
      end

  Every helper is a macro so that ExUnit reports the failure at the call site's
  file and line rather than somewhere inside this module.
  """

  @doc """
  Imports the assertion macros into the calling module.
  """
  @spec __using__(Keyword.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that `actual` is within `pct` percent of `expected`.

  The tolerance is `abs(expected) * pct / 100`. When `expected` is zero the allowed
  difference is also zero, so only an `actual` of zero passes.

      assert_within_pct(99.5, 100.0, 1)
      assert_within_pct(0, 0, 5)
  """
  @spec assert_within_pct(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_within_pct(actual, expected, pct) do
    quote do
      AssertHelpers.__within_pct__(
        unquote(actual),
        unquote(expected),
        unquote(pct),
        unquote(Macro.to_string(actual)),
        unquote(Macro.to_string(expected))
      )
    end
  end

  @doc """
  Asserts that `list` is strictly monotonic in `direction` (`:increasing` or `:decreasing`).

  Equal adjacent values are a violation. Lists with fewer than two elements trivially pass.

      assert_monotonic([1, 2, 3])
      assert_monotonic([3, 2, 1], :decreasing)
  """
  @spec assert_monotonic(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_monotonic(list, direction \\ :increasing) do
    quote do
      AssertHelpers.__monotonic__(
        unquote(list),
        unquote(direction),
        unquote(Macro.to_string(list))
      )
    end
  end

  @doc """
  Asserts that `fun` raises `exception` and that the message contains `needle`.

  Distinguishes three failure modes: nothing raised, the wrong exception type raised, or the
  right type raised with a message that does not contain `needle`.

      assert_raises_message(ArgumentError, "bad input", fn -> raise ArgumentError, "bad input" end)
  """
  @spec assert_raises_message(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_raises_message(exception, needle, fun) do
    quote do
      AssertHelpers.__raises_message__(
        unquote(exception),
        unquote(needle),
        unquote(fun),
        unquote(Macro.to_string(fun))
      )
    end
  end

  @doc """
  Runtime implementation behind `assert_within_pct/3`. Not intended to be called directly.
  """
  @spec __within_pct__(number(), number(), number(), String.t(), String.t()) :: true
  def __within_pct__(actual, expected, pct, actual_src, expected_src) do
    validate_number!(actual, "actual", actual_src)
    validate_number!(expected, "expected", expected_src)
    validate_number!(pct, "pct", "pct")

    diff = abs(actual - expected)
    allowed = abs(expected) * pct / 100

    if diff <= allowed do
      true
    else
      flunk_within_pct(actual, expected, pct, diff, allowed, actual_src, expected_src)
    end
  end

  @doc """
  Runtime implementation behind `assert_monotonic/2`. Not intended to be called directly.
  """
  @spec __monotonic__(list(), :increasing | :decreasing, String.t()) :: true
  def __monotonic__(list, direction, list_src) when direction in [:increasing, :decreasing] do
    unless is_list(list) do
      ExUnit.Assertions.flunk("""
      Expected a list for assert_monotonic

      expression: #{list_src}
      got:        #{inspect(list)}
      """)
    end

    case find_violation(list, direction) do
      nil -> true
      {index, a, b} -> flunk_monotonic(index, a, b, direction, list, list_src)
    end
  end

  def __monotonic__(_list, direction, _list_src) do
    ExUnit.Assertions.flunk("""
    Invalid direction for assert_monotonic

    expected: :increasing or :decreasing
    got:      #{inspect(direction)}
    """)
  end

  @doc """
  Runtime implementation behind `assert_raises_message/3`. Not intended to be called directly.
  """
  @spec __raises_message__(module(), String.t(), (-> any()), String.t()) :: true
  def __raises_message__(exception, needle, fun, fun_src) do
    case run_capturing(fun) do
      {:ok, value} ->
        ExUnit.Assertions.flunk("""
        Expected #{inspect(exception)} to be raised, but no exception was raised

        expression: #{fun_src}
        returned:   #{inspect(value)}
        """)

      {:raised, %{__struct__: actual_mod} = error} when actual_mod == exception ->
        message = Exception.message(error)

        if String.contains?(message, needle) do
          true
        else
          ExUnit.Assertions.flunk("""
          Expected #{inspect(exception)} message to contain #{inspect(needle)}

          expression: #{fun_src}
          message:    #{inspect(message)}
          """)
        end

      {:raised, error} ->
        ExUnit.Assertions.flunk("""
        Expected #{inspect(exception)} to be raised, but got #{inspect(error.__struct__)}

        expression: #{fun_src}
        message:    #{inspect(Exception.message(error))}
        """)
    end
  end

  # -- internals ------------------------------------------------------------------------

  @spec run_capturing((-> any())) :: {:ok, any()} | {:raised, Exception.t()}
  defp run_capturing(fun) do
    {:ok, fun.()}
  rescue
    error -> {:raised, error}
  end

  @spec find_violation(list(), :increasing | :decreasing) :: {non_neg_integer(), any(), any()} | nil
  defp find_violation(list, direction) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(fn {[a, b], index} ->
      if ordered?(a, b, direction), do: nil, else: {index, a, b}
    end)
  end

  @spec ordered?(any(), any(), :increasing | :decreasing) :: boolean()
  defp ordered?(a, b, :increasing), do: a < b
  defp ordered?(a, b, :decreasing), do: a > b

  @spec flunk_within_pct(number(), number(), number(), number(), number(), String.t(), String.t()) ::
          no_return()
  defp flunk_within_pct(actual, expected, pct, diff, allowed, actual_src, expected_src) do
    ExUnit.Assertions.flunk("""
    Expected #{actual_src} to be within #{fmt(pct)}% of #{expected_src}

    actual:              #{inspect(actual)}
    expected:            #{inspect(expected)}
    absolute difference: #{fmt(diff)}
    allowed difference:  #{fmt(allowed)}
    percentage delta:    #{pct_delta(diff, expected)}
    """)
  end

  @spec flunk_monotonic(non_neg_integer(), any(), any(), :increasing | :decreasing, list(),
          String.t()) :: no_return()
  defp flunk_monotonic(index, a, b, direction, list, list_src) do
    ExUnit.Assertions.flunk("""
    Expected #{list_src} to be strictly #{direction}, but the pair at index #{index} violates it

    index #{index}: #{inspect(a)}
    index #{index + 1}: #{inspect(b)}
    list: #{inspect(list)}
    """)
  end

  @spec pct_delta(number(), number()) :: String.t()
  defp pct_delta(_diff, expected) when expected == 0, do: "undefined (expected is zero)"
  defp pct_delta(diff, expected), do: fmt(diff / abs(expected) * 100) <> "%"

  @spec fmt(number()) :: String.t()
  defp fmt(value) when is_integer(value), do: Integer.to_string(value)
  defp fmt(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])

  @spec validate_number!(any(), String.t(), String.t()) :: :ok | no_return()
  defp validate_number!(value, label, source) do
    if is_number(value) do
      :ok
    else
      ExUnit.Assertions.flunk("""
      Expected a number for #{label} in assert_within_pct

      expression: #{source}
      got:        #{inspect(value)}
      """)
    end
  end
end