Implement the `assert_subset/2` macro in the `AssertHelpers` module below.

`assert_subset(subset, superset)` must assert that every element of the enumerable
`subset` also appears in the enumerable `superset`. Membership is set-based, so
duplicate elements in `subset` are fine — only distinct missing elements matter.

It must be a macro (not a plain function) so ExUnit reports the correct file and
line on failure. Use `quote bind_quoted: [...]` so the arguments are evaluated
exactly once. Inside the quoted body: convert both arguments to lists with
`Enum.to_list/1`, build a `MapSet` from the superset list, and collect the
elements of the subset that are not members of that set, deduplicated with
`Enum.uniq/1`.

If there are no missing elements the macro does nothing. Otherwise it must call
`ExUnit.Assertions.flunk/1` with a multi-line message that starts with
`assert_subset failed` and then reports, on separate labelled lines, the missing
elements, the subset, and the superset (each rendered with `inspect/1`).

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
  @spec __using__(Macro.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_subset/2
  # ---------------------------------------------------------------------------

  defmacro assert_subset(subset, superset) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # assert_has_keys/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `map` contains every key in `keys`.

  `keys` may be a list of keys or a single bare key. On failure the message
  lists the missing keys, the expected keys, and the keys present on the map.
  """
  @spec assert_has_keys(Macro.t(), Macro.t()) :: Macro.t()
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
  @spec assert_sorted_by(Macro.t(), Macro.t()) :: Macro.t()
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

  @doc """
  Returns the first out-of-order adjacent pair in `list` according to `key_fun`.

  Yields `:ok` when the list is sorted (non-strict ascending), or
  `{:unsorted, index, a, b}` for the first pair where `key_fun.(a) > key_fun.(b)`.
  Intended for internal use by `assert_sorted_by/2`.
  """
  @spec __first_unsorted__([term()], (term() -> term())) ::
          :ok | {:unsorted, non_neg_integer(), term(), term()}
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