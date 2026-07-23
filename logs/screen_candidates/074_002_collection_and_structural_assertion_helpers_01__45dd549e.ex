defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros focused on collections and structural data.

  `use AssertHelpers` inside a test module (typically alongside `use
  ExUnit.Case`) to import the macros. Every assertion is implemented as a
  macro so that failures are reported against the caller's file and line
  number, and every failure message is surfaced through
  `ExUnit.Assertions.flunk/1` with enough context to diagnose the problem.

  ## Example

      defmodule MyTest do
        use ExUnit.Case
        use AssertHelpers

        test "membership" do
          assert_subset([1, 2], [1, 2, 3])
        end

        test "keys" do
          assert_has_keys(%{a: 1, b: 2}, [:a, :b])
        end

        test "ordering" do
          assert_sorted_by([%{age: 20}, %{age: 40}], & &1.age)
        end
      end
  """

  @doc """
  Imports the `AssertHelpers` assertion macros into the calling module.

  Invoked automatically via `use AssertHelpers`.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that every element of `subset` also appears in `superset`.

  Membership is set-based, so duplicate elements in `subset` are allowed. On
  failure the message lists the missing elements and both collections.
  """
  @spec assert_subset(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_subset(subset, superset) do
    quote do
      sub = unquote(subset)
      sup = unquote(superset)
      sup_set = MapSet.new(sup)

      missing =
        sub
        |> Enum.reject(fn element -> MapSet.member?(sup_set, element) end)
        |> Enum.uniq()

      if missing != [] do
        ExUnit.Assertions.flunk(
          "Expected every element of subset to appear in superset.\n" <>
            "Missing elements: #{inspect(missing)}\n" <>
            "Subset:   #{inspect(sub)}\n" <>
            "Superset: #{inspect(sup)}"
        )
      end

      :ok
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
      subject = unquote(map)
      requested = unquote(keys)
      expected = if is_list(requested), do: requested, else: [requested]
      present = Map.keys(subject)
      missing = Enum.reject(expected, fn key -> Map.has_key?(subject, key) end)

      if missing != [] do
        ExUnit.Assertions.flunk(
          "Expected map to contain all required keys.\n" <>
            "Missing keys:  #{inspect(missing)}\n" <>
            "Expected keys: #{inspect(expected)}\n" <>
            "Present keys:  #{inspect(present)}"
        )
      end

      :ok
    end
  end

  @doc """
  Asserts that `enumerable` is sorted ascending (non-strict) by `key_fun`.

  `key_fun` is a 1-arity function applied to each element to compute the sort
  key; equal adjacent keys are permitted. On failure the message reports the
  zero-based `index` of the first out-of-order pair together with both
  offending elements and their computed keys.
  """
  @spec assert_sorted_by(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_sorted_by(enumerable, key_fun) do
    quote do
      list = Enum.to_list(unquote(enumerable))
      fun = unquote(key_fun)

      offending =
        list
        |> Enum.map(fn element -> {element, fun.(element)} end)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index()
        |> Enum.find(fn {[{_e1, k1}, {_e2, k2}], _idx} -> k1 > k2 end)

      case offending do
        nil ->
          :ok

        {[{first, key1}, {second, key2}], idx} ->
          ExUnit.Assertions.flunk(
            "Expected enumerable to be sorted ascending by key_fun.\n" <>
              "First out-of-order pair at index #{idx}.\n" <>
              "Element #{idx}:     #{inspect(first)} (key: #{inspect(key1)})\n" <>
              "Element #{idx + 1}: #{inspect(second)} (key: #{inspect(key2)})"
          )
      end
    end
  end
end