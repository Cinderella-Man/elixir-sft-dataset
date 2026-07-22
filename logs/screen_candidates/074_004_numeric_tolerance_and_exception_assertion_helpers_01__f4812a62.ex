defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for numeric tolerance and exception failure semantics.

  `use AssertHelpers` inside a test module to import the macros:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "rates converge" do
          assert_within_pct(99.5, 100.0, 1)
          assert_monotonic([1, 2, 3])
          assert_monotonic([3, 2, 1], :decreasing)
          assert_raises_message(ArgumentError, "bad", fn -> raise ArgumentError, "bad input" end)
        end
      end

  Every assertion is a macro so that ExUnit reports the failure at the call site's
  file and line rather than somewhere inside this module. Failures are surfaced with
  `ExUnit.Assertions.flunk/1` carrying a message that explains precisely what went wrong.
  """

  @doc """
  Imports the assertion macros into the calling module.

  Invoked via `use AssertHelpers`.
  """
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that `actual` is within `pct` percent of `expected`.

  The tolerance check is `abs(actual - expected) <= abs(expected) * pct / 100`.

  When `expected` is zero the relative tolerance collapses to zero, so only an `actual`
  of zero passes.

  ## Examples

      assert_within_pct(101, 100, 2)
      assert_within_pct(0, 0, 5)
  """
  @spec assert_within_pct(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_within_pct(actual, expected, pct) do
    quote do
      AssertHelpers.__within_pct__(unquote(actual), unquote(expected), unquote(pct))
    end
  end

  @doc """
  Asserts that `list` is strictly monotonic in `direction` (`:increasing` or `:decreasing`).

  Equal adjacent values are a violation. Lists with fewer than two elements pass trivially.

  ## Examples

      assert_monotonic([1, 2, 3])
      assert_monotonic([3.0, 1.5], :decreasing)
  """
  @spec assert_monotonic(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_monotonic(list, direction \\ :increasing) do
    quote do
      AssertHelpers.__monotonic__(unquote(list), unquote(direction))
    end
  end

  @doc """
  Asserts that `fun` raises `exception` and that its message contains the substring `needle`.

  Distinguishes three failure modes: nothing raised, the wrong exception type raised, or the
  right type raised with a message that does not contain `needle`.

  Returns the raised exception struct on success.

  ## Examples

      assert_raises_message(ArgumentError, "not a number", fn ->
        raise ArgumentError, "not a number: :foo"
      end)
  """
  @spec assert_raises_message(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_raises_message(exception, needle, fun) do
    quote do
      AssertHelpers.__raises_message__(unquote(exception), unquote(needle), unquote(fun))
    end
  end

  @doc false
  @spec __within_pct__(number(), number(), number()) :: true
  def __within_pct__(actual, expected, pct) do
    diff = abs(actual - expected)
    allowed = abs(expected) * pct / 100

    if diff <= allowed do
      true
    else
      ExUnit.Assertions.flunk("""
      Expected value within #{inspect(pct)}% tolerance.

      actual:             #{inspect(actual)}
      expected:           #{inspect(expected)}
      absolute diff:      #{inspect(diff)}
      allowed diff:       #{inspect(allowed)}
      actual pct delta:   #{format_pct(diff, expected)}
      """)
    end
  end

  @doc false
  @spec __monotonic__(list(), :increasing | :decreasing) :: true
  def __monotonic__(list, direction) when is_list(list) and direction in [:increasing, :decreasing] do
    case first_violation(list, direction) do
      nil ->
        true

      {index, a, b} ->
        ExUnit.Assertions.flunk("""
        Expected list to be strictly #{direction}, but found a violating pair.

        index:      #{index} -> #{index + 1}
        elements:   #{inspect(a)} then #{inspect(b)}
        list:       #{inspect(list)}
        """)
    end
  end

  def __monotonic__(list, direction) when is_list(list) do
    ExUnit.Assertions.flunk(
      "assert_monotonic/2 direction must be :increasing or :decreasing, got: #{inspect(direction)}"
    )
  end

  def __monotonic__(other, _direction) do
    ExUnit.Assertions.flunk("assert_monotonic/2 expected a list, got: #{inspect(other)}")
  end

  @doc false
  @spec __raises_message__(module(), String.t(), (-> any())) :: Exception.t()
  def __raises_message__(exception, needle, fun) when is_function(fun, 0) do
    result =
      try do
        fun.()
        :no_raise
      rescue
        error -> {:raised, error}
      end

    case result do
      :no_raise ->
        ExUnit.Assertions.flunk(
          "Expected #{inspect(exception)} to be raised, but no exception was raised."
        )

      {:raised, %{__struct__: ^exception} = error} ->
        message = Exception.message(error)

        if String.contains?(message, needle) do
          error
        else
          ExUnit.Assertions.flunk("""
          Expected #{inspect(exception)} message to contain #{inspect(needle)}, but it did not.

          message: #{inspect(message)}
          """)
        end

      {:raised, error} ->
        ExUnit.Assertions.flunk("""
        Expected #{inspect(exception)} to be raised, but got #{inspect(error.__struct__)}.

        message: #{inspect(Exception.message(error))}
        """)
    end
  end

  @spec format_pct(number(), number()) :: String.t()
  defp format_pct(_diff, expected) when expected in [0, +0.0, -0.0] do
    "undefined (expected is zero)"
  end

  defp format_pct(diff, expected) do
    "#{Float.round(diff / abs(expected) * 100, 6)}%"
  end

  @spec first_violation(list(), :increasing | :decreasing) :: {non_neg_integer(), any(), any()} | nil
  defp first_violation(list, direction) do
    list
    |> Enum.zip(Enum.drop(list, 1))
    |> Enum.with_index()
    |> Enum.find_value(fn {{a, b}, index} ->
      ok? =
        case direction do
          :increasing -> a < b
          :decreasing -> a > b
        end

      if ok?, do: nil, else: {index, a, b}
    end)
  end
end