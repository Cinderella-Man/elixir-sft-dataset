defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for collections and structural data.

  `use AssertHelpers` inside a test module to import the macros:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "membership" do
          assert_subset([1, 2], [1, 2, 3])
          assert_has_keys(%{a: 1, b: 2}, [:a, :b])
          assert_sorted_by([%{age: 20}, %{age: 30}], & &1.age)
        end
      end

  All three assertions are macros rather than functions so that ExUnit reports the
  file and line of the *call site* when an assertion fails. Failures are surfaced via
  `ExUnit.Assertions.flunk/1` with messages that spell out precisely what went wrong.
  """

  @doc """
  Imports the assertion macros (`assert_subset/2`, `assert_has_keys/2`,
  `assert_sorted_by/2`) into the calling module.
  """
  @spec __using__(Keyword.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers, only: [assert_subset: 2, assert_has_keys: 2, assert_sorted_by: 2]
    end
  end

  @doc """
  Asserts that every element of the enumerable `subset` also appears in `superset`.

  Membership is set-based, so duplicate elements in `subset` are irrelevant. On failure
  the message lists exactly which elements were missing along with both collections.

      assert_subset([1, 1, 2], [1, 2, 3])
  """
  @spec assert_subset(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_subset(subset, superset) do
    quote do
      AssertHelpers.__assert_subset__(unquote(subset), unquote(superset))
    end
  end

  @doc """
  Asserts that `map` contains every key in `keys`.

  `keys` may be a list of keys or a single bare key. On failure the message lists the
  missing keys, the expected keys, and the keys actually present on the map.

      assert_has_keys(%{a: 1, b: 2}, [:a, :b])
      assert_has_keys(%{a: 1}, :a)
  """
  @spec assert_has_keys(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_has_keys(map, keys) do
    quote do
      AssertHelpers.__assert_has_keys__(unquote(map), unquote(keys))
    end
  end

  @doc """
  Asserts that `enumerable` is sorted in ascending order by `key_fun`.

  The ordering is non-strict: equal adjacent keys are allowed. `key_fun` must be a
  1-arity function applied to each element to produce its sort key. On failure the
  message reports `index N` — the zero-based index of the first element of the first
  out-of-order pair — along with both offending elements and their computed keys.

      assert_sorted_by([%{age: 20}, %{age: 30}, %{age: 30}], & &1.age)
  """
  @spec assert_sorted_by(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_sorted_by(enumerable, key_fun) do
    quote do
      AssertHelpers.__assert_sorted_by__(unquote(enumerable), unquote(key_fun))
    end
  end

  @doc """
  Runtime implementation behind `assert_subset/2`. Not intended for direct use.
  """
  @spec __assert_subset__(Enumerable.t(), Enumerable.t()) :: true
  def __assert_subset__(subset, superset) do
    subset_list = Enum.to_list(subset)
    superset_list = Enum.to_list(superset)
    superset_set = MapSet.new(superset_list)

    missing =
      subset_list
      |> Enum.reject(&MapSet.member?(superset_set, &1))
      |> Enum.uniq()

    if missing == [] do
      true
    else
      ExUnit.Assertions.flunk("""
      Expected all elements of the subset to be present in the superset.

      Missing elements: #{inspect(missing)}

      Subset:   #{inspect(subset_list)}
      Superset: #{inspect(superset_list)}
      """)
    end
  end

  @doc """
  Runtime implementation behind `assert_has_keys/2`. Not intended for direct use.
  """
  @spec __assert_has_keys__(map(), list() | term()) :: true
  def __assert_has_keys__(map, keys) when is_map(map) do
    expected = List.wrap(keys)
    present = Map.keys(map)
    missing = Enum.reject(expected, &Map.has_key?(map, &1))

    if missing == [] do
      true
    else
      ExUnit.Assertions.flunk("""
      Expected the map to contain all of the given keys.

      Missing keys:  #{inspect(missing)}
      Expected keys: #{inspect(expected)}
      Actual keys:   #{inspect(present)}

      Map: #{inspect(map)}
      """)
    end
  end

  def __assert_has_keys__(other, _keys) do
    ExUnit.Assertions.flunk("""
    Expected a map, but got: #{inspect(other)}
    """)
  end

  @doc """
  Runtime implementation behind `assert_sorted_by/2`. Not intended for direct use.
  """
  @spec __assert_sorted_by__(Enumerable.t(), (term() -> term())) :: true
  def __assert_sorted_by__(enumerable, key_fun) when is_function(key_fun, 1) do
    list = Enum.to_list(enumerable)

    case first_unsorted_index(list, key_fun) do
      nil ->
        true

      index ->
        left = Enum.at(list, index)
        right = Enum.at(list, index + 1)

        ExUnit.Assertions.flunk("""
        Expected the enumerable to be sorted in ascending order by the given key function.

        Out-of-order pair at index #{index} (element #{index} sorts after element #{index + 1}).

        Element at index #{index}: #{inspect(left)}
          key: #{inspect(key_fun.(left))}

        Element at index #{index + 1}: #{inspect(right)}
          key: #{inspect(key_fun.(right))}

        Enumerable: #{inspect(list)}
        """)
    end
  end

  def __assert_sorted_by__(_enumerable, key_fun) do
    ExUnit.Assertions.flunk("""
    Expected a 1-arity key function, but got: #{inspect(key_fun)}
    """)
  end

  @spec first_unsorted_index([term()], (term() -> term())) :: non_neg_integer() | nil
  defp first_unsorted_index(list, key_fun) do
    list
    |> Enum.map(key_fun)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_index(fn [left_key, right_key] -> compare(left_key, right_key) == :gt end)
  end

  @spec compare(term(), term()) :: :lt | :eq | :gt
  defp compare(left, right) do
    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end
end