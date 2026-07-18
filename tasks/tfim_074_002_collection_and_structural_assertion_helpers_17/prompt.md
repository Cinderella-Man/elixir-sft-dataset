# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  describe "assert_subset/2" do
    test "passes when all elements are present" do
      assert_subset([1, 2], [1, 2, 3])
    end

    test "passes with duplicate elements in the subset" do
      assert_subset([1, 1, 2], [1, 2, 3])
    end

    test "passes for an empty subset" do
      assert_subset([], [1, 2, 3])
    end

    test "fails and lists the missing elements" do
      result =
        try do
          assert_subset([1, 4], [1, 2, 3])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "4"
      assert result =~ "missing"
    end

    test "failure message shows both collections" do
      message =
        try do
          assert_subset([9], [1, 2, 3])
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "subset"
      assert message =~ "superset"
    end
  end

  describe "assert_has_keys/2" do
    test "passes when the map has all keys" do
      assert_has_keys(%{a: 1, b: 2, c: 3}, [:a, :b])
    end

    test "accepts a single key (not wrapped in a list)" do
      assert_has_keys(%{a: 1}, :a)
    end

    test "passes for an empty key list" do
      assert_has_keys(%{a: 1}, [])
    end

    test "fails and lists missing keys" do
      result =
        try do
          assert_has_keys(%{a: 1}, [:a, :z])
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ ":z"
    end

    test "failure message shows the present keys" do
      # TODO
    end
  end

  describe "assert_sorted_by/2" do
    test "passes for a list sorted ascending by key" do
      people = [%{name: "A", age: 20}, %{name: "B", age: 30}, %{name: "C", age: 40}]
      assert_sorted_by(people, & &1.age)
    end

    test "passes for equal keys (non-strict ascending)" do
      assert_sorted_by([%{age: 10}, %{age: 10}], & &1.age)
    end

    test "passes for an empty list" do
      assert_sorted_by([], & &1)
    end

    test "passes for a single-element list" do
      assert_sorted_by([%{age: 5}], & &1.age)
    end

    test "fails and reports the first out-of-order pair" do
      people = [%{age: 20}, %{age: 40}, %{age: 30}]

      result =
        try do
          assert_sorted_by(people, & &1.age)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "index 1"
    end

    test "failure message includes the computed keys" do
      message =
        try do
          assert_sorted_by([%{age: 40}, %{age: 10}], & &1.age)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "key"
    end
  end
end
```
