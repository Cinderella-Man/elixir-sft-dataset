  defp take_pending(state, side, key) do
    field = pending_field(side)
    map = Map.fetch!(state, field)

    case Map.pop(map, key) do
      {nil, _rest} -> :error
      {record, rest} -> {:ok, record, Map.put(state, field, rest)}
    end
  end