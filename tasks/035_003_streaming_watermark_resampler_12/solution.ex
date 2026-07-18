  defp flush_all(%{next_emit: nil} = state), do: state

  defp flush_all(state) do
    last_bucket = floor_bucket(state.watermark, state.interval)
    do_flush(state, last_bucket)
  end