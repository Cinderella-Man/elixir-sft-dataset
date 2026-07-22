  @spec differences(state(), stream_record(), stream_record()) :: %{
          optional(atom()) => %{left: term(), right: term()}
        }
  defp differences(state, left, right) do
    state
    |> fields_to_compare(left, right)
    |> Enum.reduce(%{}, fn field, acc ->
      left_value = Map.get(left, field)
      right_value = Map.get(right, field)

      if left_value == right_value do
        acc
      else
        Map.put(acc, field, %{left: left_value, right: right_value})
      end
    end)
  end