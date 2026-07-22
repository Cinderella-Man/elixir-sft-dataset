Implement the `assert_has_keys/2` macro.

`assert_has_keys(map, keys)` asserts that `map` contains every key in `keys`.
The `keys` argument may be a list of keys or a single bare key, so it must be
normalized into a list first (use `List.wrap/1`). Determine which keys are
missing by rejecting the ones for which `Map.has_key?/2` returns true. If no
keys are missing, the assertion passes. Otherwise, call
`ExUnit.Assertions.flunk/1` with a message that lists the missing keys, the
expected keys (the normalized list), and the keys actually present on the map
(via `Map.keys/1`).

Because it is a macro (not a plain function), ExUnit can report the correct
file and line number on failure. Use `quote bind_quoted: [...]` so the `map`
and `keys` expressions are each evaluated exactly once.

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

  @doc """
  Asserts that every element of `subset` also appears in `superset`.

  Membership is set-based, so duplicate elements in `subset` are fine. On
  failure the message lists the missing elements and shows both collections.
  """
  @spec assert_subset(Macro.t(), Macro.t()) :: Macro.t()
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
  @spec assert_has_keys(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_has_keys(map, keys) do
    # TODO
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