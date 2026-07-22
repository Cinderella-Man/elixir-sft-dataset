defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for numeric tolerance and exception failure semantics.

  Intended to be `use`d inside a test module:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "tolerance" do
          assert_within_pct(99.5, 100.0, 1)
        end
      end

  All assertions are macros so that ExUnit reports the failing file and line of the
  call site rather than a location inside this module.

  Provided macros:

    * `assert_within_pct/3` — relative (percentage) numeric tolerance.
    * `assert_monotonic/2` — strict monotonicity of a list.
    * `assert_raises_message/3` — exception type plus message-substring matching.
  """

  @doc """
  Imports the assertion macros defined in this module into the caller.
  """
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that `actual` is within `pct` percent of `expected`.

  The tolerance is relative to `expected`:

      abs(actual - expected) <= abs(expected) * pct / 100

  When `expected` is zero the relative tolerance collapses to zero, so only an `actual`
  of zero passes.

  On failure the reported message includes the actual value, the expected value, the
  absolute difference, the allowed difference and the actual percentage delta.

  ## Examples

      assert_within_pct(101, 100, 2)
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
  Asserts that `list` is a strictly monotonic sequence.

  `direction` is either `:increasing` (default) or `:decreasing`. Strictness means equal
  adjacent values are a violation. Lists with fewer than two elements trivially pass.

  On failure the message reports the 0-based index of the first violating pair (rendered
  as the literal substring `index N`, where `N` is the position of the pair's first
  element) along with both elements of that pair.

  ## Examples

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
  Asserts that `fun` raises `exception` and that the raised message contains `needle`.

  `fun` must be a zero-arity function. The raised exception's message is obtained via
  `Exception.message/1` and checked for the `needle` substring.

  Three distinct failures are reported:

    * nothing was raised at all;
    * an exception of the wrong type was raised;
    * the expected type was raised but its message did not contain `needle`.

  ## Examples

      assert_raises_message(ArgumentError, "bad input", fn -> raise ArgumentError, "bad input" end)

  """
  @spec assert_raises_message(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_raises_message(exception, needle, fun) do
    quote do
      AssertHelpers.__raises_message__(
        unquote(exception),
        unquote(needle),
        unquote(fun)
      )
    end
  end

  @doc false
  @spec __within_pct__(number(), number(), number(), String.t(), String.t()) :: true
  def __within_pct__(actual, expected, pct, actual_src, expected_src) do
    validate_number!(actual, actual_src)
    validate_number!(expected, expected_src)

    diff = abs(actual - expected)
    allowed = abs(expected) * pct / 100

    if diff <= allowed do
      true
    else
      ExUnit.Assertions.flunk("""
      Expected #{actual_src} to be within #{inspect(pct)}% of #{expected_src}.

      actual:            #{inspect(actual)}
      expected:          #{inspect(expected)}
      difference:        #{inspect(diff)}
      allowed difference: #{inspect(allowed)}
      percentage delta:  #{format_pct(actual, expected)}
      """)
    end
  end

  @doc false
  @spec __monotonic__(list(), :increasing | :decreasing, String.t()) :: true
  def __monotonic__(list, direction, list_src) when is_list(list) do
    validate_direction!(direction)

    case first_violation(list, direction) do
      nil ->
        true

      {index, left, right} ->
        ExUnit.Assertions.flunk("""
        Expected #{list_src} to be strictly #{direction}, but it is not.

        violation at index #{index}: #{inspect(left)} then #{inspect(right)}
        list: #{inspect(list)}
        """)
    end
  end

  def __monotonic__(other, _direction, list_src) do
    ExUnit.Assertions.flunk(
      "Expected #{list_src} to be a list, got: #{inspect(other)}"
    )
  end

  @doc false
  @spec __raises_message__(module(), String.t(), (-> any())) :: true
  def __raises_message__(exception, needle, fun)
      when is_atom(exception) and is_binary(needle) and is_function(fun, 0) do
    try do
      fun.()
    rescue
      error ->
        check_raised(exception, needle, error)
    else
      value ->
        ExUnit.Assertions.flunk("""
        Expected #{inspect(exception)} to be raised with a message containing \
        #{inspect(needle)}, but no exception was raised.

        The function returned: #{inspect(value)}
        """)
    end
  end

  # -- internals -------------------------------------------------------------------

  @spec check_raised(module(), String.t(), Exception.t()) :: true
  defp check_raised(exception, needle, %module{} = error) when module == exception do
    message = Exception.message(error)

    if String.contains?(message, needle) do
      true
    else
      ExUnit.Assertions.flunk("""
      Expected #{inspect(exception)} message to contain #{inspect(needle)}, but the \
      message did not contain it.

      message: #{inspect(message)}
      """)
    end
  end

  defp check_raised(exception, needle, error) do
    ExUnit.Assertions.flunk("""
    Expected #{inspect(exception)} to be raised with a message containing \
    #{inspect(needle)}, but #{inspect(error.__struct__)} was raised instead.

    message: #{inspect(Exception.message(error))}
    """)
  end

  @spec first_violation(list(), :increasing | :decreasing) ::
          {non_neg_integer(), term(), term()} | nil
  defp first_violation(list, direction) do
    list
    |> Enum.zip(Enum.drop(list, 1))
    |> Enum.with_index()
    |> Enum.find_value(fn {{left, right}, index} ->
      if ordered?(left, right, direction), do: nil, else: {index, left, right}
    end)
  end

  @spec ordered?(term(), term(), :increasing | :decreasing) :: boolean()
  defp ordered?(left, right, :increasing), do: left < right
  defp ordered?(left, right, :decreasing), do: left > right

  @spec validate_direction!(term()) :: :ok
  defp validate_direction!(direction) when direction in [:increasing, :decreasing], do: :ok

  defp validate_direction!(other) do
    ExUnit.Assertions.flunk(
      "assert_monotonic/2 direction must be :increasing or :decreasing, got: #{inspect(other)}"
    )
  end

  @spec validate_number!(term(), String.t()) :: :ok
  defp validate_number!(value, _source) when is_number(value), do: :ok

  defp validate_number!(value, source) do
    ExUnit.Assertions.flunk("Expected #{source} to be a number, got: #{inspect(value)}")
  end

  @spec format_pct(number(), number()) :: String.t()
  defp format_pct(actual, expected) do
    cond do
      zero?(expected) and zero?(actual) -> "0.0%"
      zero?(expected) -> "undefined (expected is zero)"
      true -> "#{abs(actual - expected) / abs(expected) * 100}%"
    end
  end

  @spec zero?(number()) :: boolean()
  defp zero?(0), do: true
  defp zero?(+0.0), do: true
  defp zero?(-0.0), do: true
  defp zero?(_other), do: false
end