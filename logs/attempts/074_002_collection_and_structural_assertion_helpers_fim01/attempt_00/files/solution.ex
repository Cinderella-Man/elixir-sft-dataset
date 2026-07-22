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