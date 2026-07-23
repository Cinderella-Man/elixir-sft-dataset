defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for collections and structural data.

  `use AssertHelpers` inside a test module to import these macros:

    * `assert_subset/2` — every element of one enumerable is a member of another.
    * `assert_has_keys/2` — a map contains every one of the given keys.
    * `assert_sorted_by/2` — an enumerable is sorted ascending by a key function.

  Each helper is a macro so that ExUnit reports the failure at the call site
  (correct file and line number) rather than inside this module. Failures are
  surfaced through `ExUnit.Assertions.flunk/1` with a descriptive message.
  """

  @doc """
  Sets up the calling module to use the assertion macros in this module.

  Invoked automatically by `use AssertHelpers`.
  """
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that every element of `subset` is also a member of `superset`.

  Set membership is used, so duplicate elements in `subset` are fine. On
  failure the message lists exactly which elements are missing and shows both
  collections.
  """
  @spec assert_subset(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_subset(subset, superset) do
    quote do
      AssertHelpers.__assert_subset__(unquote(subset), unquote(superset))
    end
  end

  @doc """
  Asserts that `map` contains every key in `keys`.

  `keys` may be a list of keys or a single bare key. On failure the message
  lists the missing keys, the expected keys, and the keys present on the map.
  """
  @spec assert_has_keys(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_has_keys(map, keys) do
    quote do
      AssertHelpers.__assert_has_keys__(unquote(map), unquote(keys))
    end
  end

  @doc """
  Asserts that `enumerable` is sorted ascending (non-strict) by `key_fun`.

  `key_fun` is a 1-arity function applied to each element to compute its sort
  key; equal adjacent keys are allowed. On failure the message reports the
  zero-based index of the first out-of-order pair together with both offending
  elements and their computed keys.
  """
  @spec assert_sorted_by(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_sorted_by(enumerable, key_fun) do
    quote do
      AssertHelpers.__assert_sorted_by__(unquote(enumerable), unquote(key_fun))
    end
  end

  @doc false
  @spec __assert_subset__(Enumerable.t(), Enumerable.t()) :: :ok
  def __assert_subset__(subset, superset) do
    super_set = MapSet.new(superset)

    missing =
      subset
      |> Enum.filter(fn element -> not MapSet.member?(super_set, element) end)
      |> Enum.uniq()

    if missing == [] do
      :ok
    else
      ExUnit.Assertions.flunk("""
      Expected all elements of subset to appear in superset.

      Missing elements: #{inspect(missing)}
      Subset:   #{inspect(Enum.to_list(subset))}
      Superset: #{inspect(Enum.to_list(superset))}
      """)
    end
  end

  @doc false
  @spec __assert_has_keys__(map(), term()) :: :ok
  def __assert_has_keys__(map, keys) do
    expected = List.wrap(keys)
    missing = Enum.filter(expected, fn key -> not Map.has_key?(map, key) end)

    if missing == [] do
      :ok
    else
      ExUnit.Assertions.flunk("""
      Expected map to contain all keys.

      Missing keys:  #{inspect(missing)}
      Expected keys: #{inspect(expected)}
      Present keys:  #{inspect(Map.keys(map))}
      """)
    end
  end

  @doc false
  @spec __assert_sorted_by__(Enumerable.t(), (term() -> term())) :: :ok
  def __assert_sorted_by__(enumerable, key_fun) do
    list = Enum.to_list(enumerable)

    case first_out_of_order(list, key_fun) do
      :ok ->
        :ok

      {:error, index, left, right} ->
        ExUnit.Assertions.flunk("""
        Expected enumerable to be sorted in ascending order by key_fun.

        First out-of-order pair at index #{index}.
        Element[#{index}]:     #{inspect(left)} (key: #{inspect(key_fun.(left))})
        Element[#{index + 1}]: #{inspect(right)} (key: #{inspect(key_fun.(right))})
        """)
    end
  end

  @spec first_out_of_order([term()], (term() -> term())) ::
          :ok | {:error, non_neg_integer(), term(), term()}
  defp first_out_of_order([], _key_fun), do: :ok
  defp first_out_of_order([_single], _key_fun), do: :ok

  defp first_out_of_order(list, key_fun) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {[left, right], index} ->
      if key_fun.(left) <= key_fun.(right) do
        false
      else
        {:error, index, left, right}
      end
    end)
  end
end