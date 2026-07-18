  defp ensure_started(%{next_emit: nil} = state, ts) do
    %{state | next_emit: floor_bucket(ts, state.interval)}
  end

  defp ensure_started(state, _ts), do: state