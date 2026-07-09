  defp close_bucket(state, bucket) do
    agg_value =
      case Map.fetch(state.open, bucket) do
        {:ok, points} -> points |> Enum.sort_by(&elem(&1, 0)) |> aggregate(state.agg)
        :error -> nil
      end

    filled =
      case {agg_value, state.fill} do
        {nil, :forward} -> state.last_value
        {nil, nil} -> nil
        {v, _} -> v
      end

    last_value = if agg_value != nil, do: agg_value, else: state.last_value

    %{
      state
      | open: Map.delete(state.open, bucket),
        emitted: [{bucket, filled} | state.emitted],
        last_value: last_value
    }
  end