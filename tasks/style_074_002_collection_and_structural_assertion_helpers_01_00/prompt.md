# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules. This set focuses on **collections and structural data** rather than time or processes.

I need these macros:

- `assert_subset(subset, superset)` — asserts that every element of the enumerable `subset` also appears in the enumerable `superset` (set membership, so duplicates in `subset` are fine). On failure, the message should list exactly which elements are missing, plus show both collections so the developer can see what happened.

- `assert_has_keys(map, keys)` — asserts that `map` contains every key in `keys`. Accept either a list of keys or a single bare key. On failure, the message should list the missing keys, the keys that were expected, and the keys actually present on the map.

- `assert_sorted_by(enumerable, key_fun)` — asserts that `enumerable` is sorted in ascending order (non-strict, so equal adjacent keys are allowed) according to the 1-arity `key_fun` applied to each element. On failure, report the index of the first out-of-order pair together with both offending elements and their computed keys.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit`.

Give me the complete module in a single file.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for collection and structural data.

  ## Usage

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use AssertHelpers

        test "example" do
          assert_subset([:a, :b], [:a, :b, :c])
          assert_has_keys(record, [:id, :name])
          assert_sorted_by(rows, & &1.position)
        end
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_subset/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that every element of `subset` also appears in `superset`.

  Membership is set-based, so duplicate elements in `subset` are fine. On
  failure the message lists the missing elements and shows both collections.
  """
  defmacro assert_subset(subset, superset) do
    quote bind_quoted: [subset: subset, superset: superset] do
      sub_list = Enum.to_list(subset)
      sup_list = Enum.to_list(superset)
      sup_set = MapSet.new(sup_list)

      missing =
        sub_list
        |> Enum.reject(fn el -> MapSet.member?(sup_set, el) end)
        |> Enum.uniq()

      unless missing == [] do
        ExUnit.Assertions.flunk("""
        assert_subset failed

          expected every element of the subset to appear in the superset
          missing elements: #{inspect(missing)}
          subset          : #{inspect(sub_list)}
          superset        : #{inspect(sup_list)}
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_has_keys/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `map` contains every key in `keys`.

  `keys` may be a list of keys or a single bare key. On failure the message
  lists the missing keys, the expected keys, and the keys present on the map.
  """
  defmacro assert_has_keys(map, keys) do
    quote bind_quoted: [map: map, keys: keys] do
      key_list = List.wrap(keys)
      missing = Enum.reject(key_list, fn k -> Map.has_key?(map, k) end)

      unless missing == [] do
        ExUnit.Assertions.flunk("""
        assert_has_keys failed

          missing keys  : #{inspect(missing)}
          expected keys : #{inspect(key_list)}
          present keys  : #{inspect(Map.keys(map))}
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_sorted_by/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `enumerable` is sorted in ascending (non-strict) order according
  to `key_fun` applied to each element.

  On failure the message reports the index of the first out-of-order pair,
  both offending elements, and their computed keys.
  """
  defmacro assert_sorted_by(enumerable, key_fun) do
    quote bind_quoted: [enumerable: enumerable, key_fun: key_fun] do
      list = Enum.to_list(enumerable)

      case AssertHelpers.__first_unsorted__(list, key_fun) do
        :ok ->
          :ok

        {:unsorted, index, a, b} ->
          ExUnit.Assertions.flunk("""
          assert_sorted_by failed

            list is not sorted in ascending order by the given key function
            first out-of-order pair at index #{index}:
              element #{index}     : #{inspect(a)} (key: #{inspect(key_fun.(a))})
              element #{index + 1} : #{inspect(b)} (key: #{inspect(key_fun.(b))})
            full list: #{inspect(list)}
          """)
      end
    end
  end

  # Public so the macro-generated `quote` block can call it from any module.
  @doc false
  def __first_unsorted__(list, key_fun) do
    list
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {[a, b], i} ->
      if key_fun.(a) > key_fun.(b), do: {:unsorted, i, a, b}, else: false
    end)
  end
end
```

The style review said:

```
The solution is green but does not meet the house style: no @spec on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/074_002_collection_and_structural_assertion_helpers_01/attempt_0 -->
